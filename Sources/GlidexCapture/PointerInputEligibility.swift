import AppKit
import CoreGraphics
import GlidexCore

enum PointerInputEligibility {
    static func hostWindowNumber(for target: SimulatorWindowTracker.Target) -> Int? {
        PointerInputPolicy.hostWindowNumber(
            ownerPID: target.ownerPID,
            windowFrame: target.windowFrame,
            frontToBackWindows: onScreenWindows()
        )
    }

    @MainActor
    static func isEligible(pointer: DesktopPoint, overlay: OverlayWindowController) -> Bool {
        PointerInputPolicy.allowsInput(
            pointer: pointer,
            simulatorFrame: overlay.frame,
            overlayWindowNumber: overlay.windowNumber,
            hitWindowNumber: NSWindow.windowNumber(
                at: pointer.cgPoint,
                belowWindowWithWindowNumber: 0
            )
        )
    }

    @MainActor
    static func isSimulatorVisible(overlay: OverlayWindowController) -> Bool {
        isEligible(
            pointer: DesktopPoint(x: overlay.frame.midX, y: overlay.frame.midY),
            overlay: overlay
        )
    }

    private static func onScreenWindows() -> [DesktopWindowRecord] {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }
        let coordinateSpace = DesktopCoordinateSpace(
            mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
        )
        return entries.compactMap { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID] as? NSNumber,
                  let windowNumber = entry[kCGWindowNumber] as? NSNumber,
                  let layer = entry[kCGWindowLayer] as? NSNumber,
                  let bounds = entry[kCGWindowBounds] as? NSDictionary,
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return DesktopWindowRecord(
                ownerPID: ownerPID.int32Value,
                windowNumber: windowNumber.intValue,
                layer: layer.intValue,
                frame: coordinateSpace.appKitFrame(fromQuartzTopLeft: quartzFrame)
            )
        }
    }
}
