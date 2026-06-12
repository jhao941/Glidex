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

    @Test("finger convergence resolves to pinch")
    func pinchInIntent() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.42, 0.5), second: point(0.58, 0.5)))

        guard case let .began(gesture) = output else {
            Issue.record("expected pinch-in to begin")
            return
        }
        #expect(gesture.intent == .pinch)
    }

    @Test("pinch reports rotation relative to its initial finger axis")
    func pinchRotation() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        _ = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.38, 0.5), second: point(0.62, 0.5)))
        let output = interpreter.consume(frame(3, timestamp: 0.04, first: point(0.4, 0.4), second: point(0.6, 0.6)))

        guard case let .changed(gesture) = output else {
            Issue.record("expected rotating pinch update")
            return
        }
        #expect(abs(gesture.rotationDelta - .pi / 4) < 0.001)
    }

    @Test("same-direction fingers with unequal speed remain navigation")
    func unequalSpeedSwipe() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.41, 0.5), second: point(0.63, 0.5)))

        guard case let .began(gesture) = output else {
            Issue.record("expected unequal-speed swipe to begin navigation")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("diagonal unequal-speed movement remains navigation")
    func diagonalUnequalSpeedSwipe() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.4), second: point(0.6, 0.4))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.41, 0.42), second: point(0.63, 0.45)))

        guard case let .began(gesture) = output else {
            Issue.record("expected diagonal unequal-speed swipe to begin navigation")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("vertical swipe tolerates opposing horizontal jitter")
    func verticalSwipeWithHorizontalJitter() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.4), second: point(0.6, 0.4))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.398, 0.43), second: point(0.602, 0.45)))

        guard case let .began(gesture) = output else {
            Issue.record("expected vertical swipe with lateral jitter to begin navigation")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("brief opposing start remains pending and can resolve as navigation")
    func opposingStartThenSwipe() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        #expect(interpreter.consume(frame(2, timestamp: 0.01, first: point(0.394, 0.5), second: point(0.607, 0.5))) == .pending)

        let output = interpreter.consume(frame(3, timestamp: 0.03, first: point(0.42, 0.5), second: point(0.63, 0.5)))
        guard case let .began(gesture) = output else {
            Issue.record("expected opposing startup noise to resolve as navigation")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("initial one-finger lead does not claim pinch before swipe direction is clear")
    func staggeredSwipeStart() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        #expect(interpreter.consume(frame(2, timestamp: 0.02, first: point(0.4, 0.5), second: point(0.62, 0.5))) == .pending)

        let output = interpreter.consume(frame(3, timestamp: 0.04, first: point(0.42, 0.5), second: point(0.65, 0.5)))
        guard case let .began(gesture) = output else {
            Issue.record("expected staggered swipe to resolve as navigation")
            return
        }
        #expect(gesture.intent == .navigate)
    }

    @Test("pinch requires opposing movement along the finger axis")
    func sameDirectionSeparationIsNotPinch() {
        var interpreter = GestureInterpreter()

        #expect(interpreter.consume(frame(1, timestamp: 0, first: point(0.4, 0.5), second: point(0.6, 0.5))) == .pending)
        let output = interpreter.consume(frame(2, timestamp: 0.02, first: point(0.42, 0.5), second: point(0.65, 0.5)))

        guard case let .began(gesture) = output else {
            Issue.record("expected same-direction separation to resolve")
            return
        }
        #expect(gesture.intent == .navigate)
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

    private func frame(_ number: Int32, timestamp: Double, first: NormalizedTouchPoint, second: NormalizedTouchPoint) -> RawTouchFrame {
        RawTouchFrame(
            timestamp: timestamp,
            frame: number,
            contacts: [contact(id: 1, state: 4, at: first), contact(id: 2, state: 4, at: second)]
        )
    }

    private func contact(id: Int32, state: Int32, at point: NormalizedTouchPoint) -> RawTouchContact {
        RawTouchContact(
            identifier: id,
            state: state,
            normalizedPosition: point,
            normalizedVelocity: .zero,
            size: 1
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> NormalizedTouchPoint {
        NormalizedTouchPoint(x: x, y: y)
    }
}
