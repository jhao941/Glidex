import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("Pointer input policy")
struct PointerInputPolicyTests {
    private let simulatorFrame = CGRect(x: 100, y: 100, width: 300, height: 600)

    @Test("host window is matched by owner and top-level frame")
    func hostWindowMatch() {
        let windows = [
            DesktopWindowRecord(ownerPID: 90, windowNumber: 3, frame: simulatorFrame),
            DesktopWindowRecord(ownerPID: 42, windowNumber: 7, frame: simulatorFrame),
        ]
        #expect(PointerInputPolicy.hostWindowNumber(
            ownerPID: 42,
            windowFrame: simulatorFrame,
            frontToBackWindows: windows
        ) == 7)
    }

    @Test("non-top-level windows are not selected as the host")
    func ignoresChildWindows() {
        let windows = [
            DesktopWindowRecord(ownerPID: 42, windowNumber: 6, layer: 1, frame: simulatorFrame),
            DesktopWindowRecord(ownerPID: 42, windowNumber: 7, frame: simulatorFrame),
        ]
        #expect(PointerInputPolicy.hostWindowNumber(
            ownerPID: 42,
            windowFrame: simulatorFrame,
            frontToBackWindows: windows
        ) == 7)
    }

    @Test("distant windows do not produce an unsafe host match")
    func rejectsDistantWindow() {
        let windows = [
            DesktopWindowRecord(
                ownerPID: 42,
                windowNumber: 7,
                frame: simulatorFrame.offsetBy(dx: 30, dy: 0)
            ),
        ]
        #expect(PointerInputPolicy.hostWindowNumber(
            ownerPID: 42,
            windowFrame: simulatorFrame,
            frontToBackWindows: windows
        ) == nil)
    }

    @Test("system hit testing allows the overlay")
    func overlayHit() {
        #expect(PointerInputPolicy.allowsInput(
            pointer: DesktopPoint(x: 200, y: 300),
            simulatorFrame: simulatorFrame,
            overlayWindowNumber: 2,
            hitWindowNumber: 2
        ))
    }

    @Test("system hit testing blocks a covering window")
    func covered() {
        #expect(!PointerInputPolicy.allowsInput(
            pointer: DesktopPoint(x: 200, y: 300),
            simulatorFrame: simulatorFrame,
            overlayWindowNumber: 2,
            hitWindowNumber: 9
        ))
    }

    @Test("pointer outside the simulator is rejected")
    func outside() {
        #expect(!PointerInputPolicy.allowsInput(
            pointer: DesktopPoint(x: 50, y: 50),
            simulatorFrame: simulatorFrame,
            overlayWindowNumber: 2,
            hitWindowNumber: 2
        ))
    }
}
