import Foundation
import Testing
@testable import GlidexCore

@Suite("TouchTransaction")
struct TouchTransactionTests {
    @Test("a transaction emits at most one begin and one end")
    func lifecycleIsIdempotent() {
        let sink = RecordingTouchSink()
        let transaction = makeTransaction(sink: sink)
        let start = [contact(10, 20)]
        let end = [contact(30, 40)]

        #expect(transaction.begin(contacts: start))
        #expect(!transaction.begin(contacts: start))
        #expect(transaction.end(contacts: end))
        #expect(!transaction.end(contacts: end))
        #expect(!transaction.cancel())

        #expect(sink.events.count == 2)
        #expect(sink.events[0] == .begin(snapshot(contacts: start)))
        #expect(sink.events[1] == .end(snapshot(contacts: end)))
    }

    @Test("duplicate updates are suppressed")
    func duplicateUpdates() {
        let sink = RecordingTouchSink()
        let transaction = makeTransaction(sink: sink)
        let start = [contact(10, 20)]
        let moved = [contact(11, 21)]

        #expect(transaction.begin(contacts: start))
        #expect(!transaction.update(contacts: start))
        #expect(transaction.update(contacts: moved))
        #expect(!transaction.update(contacts: moved))

        #expect(sink.events.count == 2)
        #expect(sink.events[1] == .update(snapshot(contacts: moved)))
    }

    @Test("cancel releases an active transaction once")
    func cancelIsTerminal() {
        let sink = RecordingTouchSink()
        let transaction = makeTransaction(sink: sink)
        let start = [contact(10, 20)]

        #expect(transaction.begin(contacts: start))
        #expect(transaction.cancel())
        #expect(!transaction.cancel())
        #expect(!transaction.end())
        #expect(sink.events == [.begin(snapshot(contacts: start)), .cancel(snapshot(contacts: start))])
    }

    private func makeTransaction(sink: RecordingTouchSink) -> TouchTransaction {
        TouchTransaction(
            gestureID: TestFixtures.gestureID,
            source: .mouse,
            intent: .point,
            anchor: TestFixtures.anchor,
            sink: sink
        )
    }

    private func contact(_ x: CGFloat, _ y: CGFloat) -> TouchContactPoint {
        TouchContactPoint(identifier: 0, point: SimulatorPoint(x: x, y: y))
    }

    private func snapshot(contacts: [TouchContactPoint]) -> TouchTransactionSnapshot {
        TouchTransactionSnapshot(
            gestureID: TestFixtures.gestureID,
            source: .mouse,
            intent: .point,
            anchor: TestFixtures.anchor,
            contacts: contacts
        )
    }
}

private enum TestFixtures {
    static let gestureID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    static let anchor = SimulatorPoint(x: 10, y: 20)
}

private final class RecordingTouchSink: TouchSink {
    private(set) var events: [TouchLifecycleEvent] = []

    func receive(_ event: TouchLifecycleEvent) {
        events.append(event)
    }
}
