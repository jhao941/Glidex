import Foundation
import Testing
@testable import GlidexCore

@Suite("Touch logging")
struct TouchLoggingTests {
    @Test("lifecycle events retain structured context")
    func structuredContext() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let snapshot = TouchTransactionSnapshot(
            gestureID: id,
            source: .rawTrackpad,
            intent: .navigate,
            anchor: SimulatorPoint(x: 100, y: 200),
            contacts: [TouchContactPoint(identifier: 0, point: SimulatorPoint(x: 110, y: 210))]
        )
        let record = TouchLogRecord(event: .cancel(snapshot))

        #expect(record.gestureID == id)
        #expect(record.source == .rawTrackpad)
        #expect(record.intent == .navigate)
        #expect(record.anchor == SimulatorPoint(x: 100, y: 200))
        #expect(record.phase == .cancel)
        #expect(record.message.contains("phase=cancel"))
    }
}
