import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("DirectTouchMapper")
struct DirectTouchMapperTests {
    private let coordinateMapper = CoordinateMapper(
        captureRect: .zero,
        simulatorSize: SimulatorPointSize(width: 400, height: 800)
    )

    @Test("single contact maps directly through begin, change, and end")
    func singleContactLifecycle() {
        var mapper = makeMapper()

        #expect(mapper.consume(frame(1, [contact(9, x: 0.25, y: 0.75)])) == .began([
            mappedContact(9, x: 100, y: 200),
        ]))
        #expect(mapper.consume(frame(2, [contact(9, x: 0.5, y: 0.25)])) == .changed([
            mappedContact(9, x: 200, y: 600),
        ]))
        #expect(mapper.consume(frame(3, [contact(9, state: 7, x: 0.6, y: 0.2)])) == .ended([
            mappedContact(9, x: 240, y: 640),
        ]))
    }

    @Test("contact order does not create a false update")
    func stableContactOrder() {
        var mapper = makeMapper()
        let first = contact(20, x: 0.75, y: 0.25)
        let second = contact(10, x: 0.125, y: 0.875)

        #expect(mapper.consume(frame(1, [first, second])) == .began([
            mappedContact(10, x: 50, y: 100),
            mappedContact(20, x: 300, y: 600),
        ]))
        #expect(mapper.consume(frame(2, [second, first])) == nil)
    }

    @Test("contacts can join and leave without restarting the gesture")
    func changingContactSet() {
        var mapper = makeMapper()
        let first = contact(3, x: 0.25, y: 0.75)
        let second = contact(7, x: 0.75, y: 0.25)

        #expect(mapper.consume(frame(1, [first])) == .began([
            mappedContact(3, x: 100, y: 200),
        ]))
        #expect(mapper.consume(frame(2, [second, first])) == .changed([
            mappedContact(3, x: 100, y: 200),
            mappedContact(7, x: 300, y: 600),
        ]))
        #expect(mapper.consume(frame(3, [contact(3, state: 7, x: 0.25, y: 0.75), second])) == .changed([
            mappedContact(7, x: 300, y: 600),
        ]))
        #expect(mapper.consume(frame(4, [])) == .ended([
            mappedContact(7, x: 300, y: 600),
        ]))
    }

    @Test("simultaneous release preserves final positions")
    func simultaneousRelease() {
        var mapper = makeMapper()
        #expect(mapper.consume(frame(1, [
            contact(1, x: 0.25, y: 0.25),
            contact(2, x: 0.75, y: 0.75),
        ])) != nil)

        #expect(mapper.consume(frame(2, [
            contact(2, state: 7, x: 0.625, y: 0.625),
            contact(1, state: 7, x: 0.375, y: 0.375),
        ])) == .ended([
            mappedContact(1, x: 150, y: 500),
            mappedContact(2, x: 250, y: 300),
        ]))
    }

    @Test("coordinates are clamped to simulator bounds")
    func coordinateClamping() {
        var mapper = makeMapper()
        #expect(mapper.consume(frame(1, [contact(1, x: -0.5, y: 1.5)])) == .began([
            mappedContact(1, x: 0, y: 0),
        ]))
    }

    @Test("duplicate frames and unchanged positions are suppressed")
    func duplicateFrames() {
        var mapper = makeMapper()
        let touch = contact(1, x: 0.5, y: 0.5)
        #expect(mapper.consume(frame(1, [touch])) != nil)
        #expect(mapper.consume(frame(1, [contact(1, x: 0.6, y: 0.5)])) == nil)
        #expect(mapper.consume(frame(2, [touch])) == nil)
    }

    @Test("cancellation releases the current contacts once")
    func cancellation() {
        var mapper = makeMapper()
        #expect(mapper.cancel() == nil)
        #expect(mapper.consume(frame(1, [contact(4, x: 0.4, y: 0.6)])) != nil)
        #expect(mapper.cancel() == .cancelled([mappedContact(4, x: 160, y: 320)]))
        #expect(mapper.cancel() == nil)
    }

    private func makeMapper() -> DirectTouchMapper {
        DirectTouchMapper(coordinateMapper: coordinateMapper)
    }

    private func frame(_ number: Int32, _ contacts: [RawTouchContact]) -> RawTouchFrame {
        RawTouchFrame(timestamp: Double(number) / 100, frame: number, contacts: contacts)
    }

    private func contact(
        _ identifier: Int32,
        state: Int32 = 4,
        x: CGFloat,
        y: CGFloat
    ) -> RawTouchContact {
        RawTouchContact(
            identifier: identifier,
            state: state,
            normalizedPosition: NormalizedTouchPoint(x: x, y: y),
            normalizedVelocity: .zero,
            size: 1
        )
    }

    private func mappedContact(_ identifier: Int, x: CGFloat, y: CGFloat) -> TouchContactPoint {
        TouchContactPoint(identifier: identifier, point: SimulatorPoint(x: x, y: y))
    }
}
