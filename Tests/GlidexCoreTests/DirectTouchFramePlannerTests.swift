import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("Direct Touch frame planner")
struct DirectTouchFramePlannerTests {
    @Test("contacts retain identity while fingers join and leave")
    func changingContacts() {
        let previous = [contact(1, x: 10), contact(2, x: 20)]
        let next = [contact(2, x: 25), contact(3, x: 30)]

        let frames = DirectTouchFramePlanner.update(from: previous, to: next)

        #expect(frames.count == 1)
        #expect(frames[0].map(\.identifier) == [1, 2, 3])
        #expect(frames[0].map(\.phase) == [.up, .move, .down])
        #expect(frames[0][1].point.x == 25)
    }

    @Test("replacing a contact at five-finger capacity uses release then addition frames")
    func replacementAtCapacity() {
        let previous = (1...5).map { contact($0, x: CGFloat($0 * 10)) }
        let next = (2...6).map { contact($0, x: CGFloat($0 * 10)) }

        let frames = DirectTouchFramePlanner.update(from: previous, to: next)

        #expect(frames.count == 2)
        #expect(frames[0].count == 5)
        #expect(frames[0].first?.identifier == 1)
        #expect(frames[0].first?.phase == .up)
        #expect(frames[1].count == 5)
        #expect(frames[1].last?.identifier == 6)
        #expect(frames[1].last?.phase == .down)
    }

    @Test("ending preserves final positions and lifts every active contact")
    func endingContacts() {
        let contacts = [contact(1, x: 10), contact(2, x: 20)]
        let final = [contact(1, x: 15), contact(2, x: 25)]

        let frame = DirectTouchFramePlanner.end(currentContacts: contacts, finalContacts: final)

        #expect(frame.map(\.phase) == [.up, .up])
        #expect(frame.map { $0.point.x } == [15, 25])
    }

    private func contact(_ identifier: Int, x: CGFloat) -> TouchContactPoint {
        TouchContactPoint(identifier: identifier, point: SimulatorPoint(x: x, y: 100))
    }
}
