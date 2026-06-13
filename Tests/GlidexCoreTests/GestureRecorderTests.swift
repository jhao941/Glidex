import Foundation
import Testing
@testable import GlidexCore

@Suite("Gesture recorder")
struct GestureRecorderTests {
    @Test("records normalized lifecycle events with monotonic relative timing")
    func recordsLifecycle() throws {
        let clock = TestRecordingClock(10)
        let recorder = GestureRecorder(timeProvider: { clock.now })
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        try recorder.start(
            name: "  Pinch Demo  ",
            sourceScreen: SimulatorPointSize(width: 400, height: 800),
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        recorder.record(.begin(snapshot(id: id, contacts: [contact(2, 300, 600), contact(1, 100, 200)])))
        clock.now = 10.25
        recorder.record(.update(snapshot(id: id, contacts: [contact(1, 80, 160), contact(2, 320, 640)])))
        clock.now = 10.5
        recorder.record(.end(snapshot(id: id, contacts: [contact(1, 80, 160), contact(2, 320, 640)])))

        let recording = try #require(recorder.stop())
        #expect(recording.name == "Pinch Demo")
        #expect(recording.sourceScreen == RecordingScreen(width: 400, height: 800))
        #expect(recording.events.map(\.time) == [0, 0.25, 0.5])
        #expect(recording.events.map(\.phase) == [.begin, .update, .end])
        #expect(recording.events[0].contacts.map(\.id) == [1, 2])
        #expect(recording.events[0].contacts[0] == RecordedTouchContact(id: 1, x: 0.25, y: 0.25))
        #expect(recording.events[0].anchorX == 0.5)
        #expect(recording.events[0].anchorY == 0.5)
    }

    @Test("ignores a gesture already in progress when recording starts")
    func ignoresPartialGesture() throws {
        let clock = TestRecordingClock(1)
        let recorder = GestureRecorder(timeProvider: { clock.now })
        let partialID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let completeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        try recorder.start(name: "Test", sourceScreen: SimulatorPointSize(width: 100, height: 200))
        recorder.record(.update(snapshot(id: partialID, contacts: [contact(1, 20, 40)])))
        recorder.record(.end(snapshot(id: partialID, contacts: [contact(1, 20, 40)])))
        recorder.record(.begin(snapshot(id: completeID, contacts: [contact(2, 30, 60)])))
        recorder.record(.end(snapshot(id: completeID, contacts: [contact(2, 30, 60)])))

        let recording = try #require(recorder.stop())
        #expect(recording.events.count == 2)
        #expect(recording.events.allSatisfy { $0.gestureID == completeID })
    }

    @Test("stopping appends cancellation for every active gesture")
    func stopCancelsActiveGestures() throws {
        let clock = TestRecordingClock(5)
        let recorder = GestureRecorder(timeProvider: { clock.now })
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        try recorder.start(name: "Drag", sourceScreen: SimulatorPointSize(width: 100, height: 200))
        recorder.record(.begin(snapshot(id: id, contacts: [contact(1, 20, 40)])))
        clock.now = 5.5
        recorder.record(.update(snapshot(id: id, contacts: [contact(1, 30, 50)])))
        clock.now = 6

        let recording = try #require(recorder.stop())
        #expect(recording.events.map(\.phase) == [.begin, .update, .cancel])
        #expect(recording.events.last?.time == 1)
        #expect(recording.events.last?.contacts.first?.x == 0.3)
    }

    @Test("JSON codec preserves the public format and rejects unsupported versions")
    func codecRoundTrip() throws {
        let recording = GestureRecording(
            name: "Tap",
            recordedAt: Date(timeIntervalSince1970: 1_000),
            sourceScreen: RecordingScreen(width: 400, height: 800),
            events: [RecordedTouchEvent(
                time: 0,
                gestureID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                phase: .begin,
                source: .mouse,
                intent: .point,
                anchorX: 0.5,
                anchorY: 0.5,
                contacts: [RecordedTouchContact(id: 0, x: 0.25, y: 0.75)]
            )]
        )

        let data = try GestureRecordingCodec.encode(recording)
        #expect(try GestureRecordingCodec.decode(data) == recording)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"formatVersion\" : 1"))
        #expect(json.contains("\"recordedAt\" : \"1970-01-01T00:16:40Z\""))

        let unsupported = Data(json.replacingOccurrences(
            of: "\"formatVersion\" : 1",
            with: "\"formatVersion\" : 99"
        ).utf8)
        #expect(throws: GestureRecordingError.unsupportedFormatVersion(99)) {
            try GestureRecordingCodec.decode(unsupported)
        }
    }

    @Test("invalid screen sizes and duplicate starts are rejected")
    func invalidState() throws {
        let recorder = GestureRecorder(timeProvider: { 0 })
        #expect(throws: GestureRecordingError.invalidSourceScreen) {
            try recorder.start(name: "Invalid", sourceScreen: SimulatorPointSize(width: 0, height: 800))
        }
        try recorder.start(name: "Valid", sourceScreen: SimulatorPointSize(width: 400, height: 800))
        #expect(throws: GestureRecordingError.alreadyRecording) {
            try recorder.start(name: "Again", sourceScreen: SimulatorPointSize(width: 400, height: 800))
        }
    }

    private func snapshot(id: UUID, contacts: [TouchContactPoint]) -> TouchTransactionSnapshot {
        TouchTransactionSnapshot(
            gestureID: id,
            source: .rawTrackpad,
            intent: .pinch,
            anchor: SimulatorPoint(x: 200, y: 400),
            contacts: contacts
        )
    }

    private func contact(_ id: Int, _ x: CGFloat, _ y: CGFloat) -> TouchContactPoint {
        TouchContactPoint(identifier: id, point: SimulatorPoint(x: x, y: y))
    }
}

private final class TestRecordingClock: @unchecked Sendable {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}
