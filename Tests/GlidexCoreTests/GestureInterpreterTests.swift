import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("GestureInterpreter")
struct GestureInterpreterTests {
    @Test("centroid movement resolves to navigation")
    func navigationIntent() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.42, 0.5), second: point(0.62, 0.5)))

        guard case let .began(gesture) = output else {
            Issue.record("expected navigation to begin")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("finger separation resolves to pinch")
    func pinchIntent() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.38, 0.5), second: point(0.62, 0.5)))

        guard case let .began(gesture) = output else {
            Issue.record("expected pinch to begin")
            return
        }
        #expect(gesture.intent == .pinch)
    }

    @Test("duplicate frame numbers do not emit duplicate events")
    func duplicateFrames() {
        var interpreter = GestureInterpreter()
        let initial = frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))

        #expect(interpreter.consume(initial) == .pending)
        #expect(interpreter.consume(initial) == nil)
    }

    @Test("tracked contact release ends once")
    func releaseEndsGesture() {
        var interpreter = GestureInterpreter()
        _ = interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5)))
        _ = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.42, 0.5), second: point(0.62, 0.5)))

        let released = RawTouchFrame(
            timestamp: 0.03,
            frame: 3,
            contacts: [contact(id: 1, state: 7, at: point(0.42, 0.5)), contact(id: 2, state: 4, at: point(0.62, 0.5))]
        )
        #expect(interpreter.consume(released) == .ended)
        #expect(interpreter.consume(RawTouchFrame(timestamp: 0.04, frame: 4, contacts: [])) == nil)
    }

    private func frame(_ number: Int32, timestamp: Double, first: CGPoint, second: CGPoint) -> RawTouchFrame {
        RawTouchFrame(
            timestamp: timestamp,
            frame: number,
            contacts: [contact(id: 1, state: 4, at: first), contact(id: 2, state: 4, at: second)]
        )
    }

    private func contact(id: Int32, state: Int32, at point: CGPoint) -> RawTouchContact {
        RawTouchContact(
            identifier: id,
            state: state,
            normalizedPosition: point,
            normalizedVelocity: .zero,
            size: 1
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }
}
