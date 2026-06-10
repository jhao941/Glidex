import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("Mouse gesture lifecycle")
struct MouseGestureStateMachineTests {
    @Test("mouse down stays pending and mouse up creates one tap")
    func tap() {
        var machine = MouseGestureStateMachine(threshold: 3)
        #expect(machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20)).isEmpty)
        #expect(machine.mouseUp(capture: capture(11, 10), simulator: simulator(22, 20)) == [.tap(simulator(20, 20))])
        #expect(machine.mouseUp(capture: capture(11, 10), simulator: simulator(22, 20)).isEmpty)
    }

    @Test("drag begins at the original coordinate only after threshold")
    func dragThreshold() {
        var machine = MouseGestureStateMachine(threshold: 3)
        _ = machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20))
        #expect(machine.mouseDragged(capture: capture(12, 10), simulator: simulator(24, 20)).isEmpty)
        #expect(machine.mouseDragged(capture: capture(14, 10), simulator: simulator(28, 20)) == [
            .beginDrag(start: simulator(20, 20), current: simulator(28, 20)),
        ])
        #expect(machine.mouseUp(capture: capture(16, 10), simulator: simulator(32, 20)) == [.endDrag(simulator(32, 20))])
    }

    @Test("short drag delivered only at mouse up never becomes a tap")
    func shortDragAtMouseUp() {
        var machine = MouseGestureStateMachine(threshold: 3)
        _ = machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20))
        #expect(machine.mouseUp(capture: capture(14, 10), simulator: simulator(28, 20)) == [
            .beginDrag(start: simulator(20, 20), current: simulator(28, 20)),
            .endDrag(simulator(28, 20)),
        ])
    }

    @Test("rapid reversal stays one drag lifecycle")
    func rapidReversal() {
        var machine = MouseGestureStateMachine(threshold: 3)
        _ = machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20))
        #expect(machine.mouseDragged(capture: capture(20, 10), simulator: simulator(40, 20)).count == 1)
        #expect(machine.mouseDragged(capture: capture(5, 10), simulator: simulator(10, 20)) == [.updateDrag(simulator(10, 20))])
        #expect(machine.mouseUp(capture: capture(5, 10), simulator: simulator(10, 20)) == [.endDrag(simulator(10, 20))])
    }

    @Test("cancel pending emits nothing while cancel drag releases once")
    func cancellation() {
        var machine = MouseGestureStateMachine(threshold: 3)
        _ = machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20))
        #expect(machine.cancel() == nil)
        _ = machine.mouseDown(capture: capture(10, 10), simulator: simulator(20, 20))
        _ = machine.mouseDragged(capture: capture(20, 10), simulator: simulator(40, 20))
        #expect(machine.cancel() == .cancelDrag)
        #expect(machine.cancel() == nil)
    }

    private func capture(_ x: CGFloat, _ y: CGFloat) -> CapturePoint { CapturePoint(x: x, y: y) }
    private func simulator(_ x: CGFloat, _ y: CGFloat) -> SimulatorPoint { SimulatorPoint(x: x, y: y) }
}
