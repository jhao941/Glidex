import CoreGraphics
import Foundation

public struct DesktopWindowRecord: Equatable, Sendable {
    public var ownerPID: pid_t
    public var windowNumber: Int
    public var layer: Int
    public var frame: CGRect

    public init(ownerPID: pid_t, windowNumber: Int, layer: Int = 0, frame: CGRect) {
        self.ownerPID = ownerPID
        self.windowNumber = windowNumber
        self.layer = layer
        self.frame = frame
    }
}

public enum PointerInputPolicy {
    public static func hostWindowNumber(
        ownerPID: pid_t,
        windowFrame: CGRect,
        frontToBackWindows: [DesktopWindowRecord]
    ) -> Int? {
        frontToBackWindows
            .filter { $0.ownerPID == ownerPID && $0.layer == 0 }
            .min(by: {
                frameDistance($0.frame, windowFrame) < frameDistance($1.frame, windowFrame)
            })
            .flatMap { frameDistance($0.frame, windowFrame) <= 8 ? $0.windowNumber : nil }
    }

    public static func allowsInput(
        pointer: DesktopPoint,
        simulatorFrame: CGRect,
        overlayWindowNumber: Int,
        hitWindowNumber: Int
    ) -> Bool {
        simulatorFrame.contains(pointer.cgPoint) && hitWindowNumber == overlayWindowNumber
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) +
            abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }
}
