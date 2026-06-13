import Foundation
import Testing
@testable import GlidexCore

@Suite("Gesture replay engine")
@MainActor
struct GestureReplayEngineTests {
    @Test("plan maps normalized coordinates and replaces recorded gesture IDs")
    func mapsCoordinates() throws {
        let recordedID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let replayID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let plan = try GestureReplayPlan(
            recording: recording(id: recordedID),
            targetScreen: SimulatorPointSize(width: 200, height: 400),
            gestureIDProvider: { replayID }
        )

        #expect(plan.steps.map(\.time) == [0, 0.25, 0.5])
        let snapshots = plan.steps.compactMap(\.event.snapshot)
        #expect(snapshots.allSatisfy { $0.gestureID == replayID })
        #expect(snapshots[0].anchor == SimulatorPoint(x: 100, y: 200))
        #expect(snapshots[0].contacts == [
            TouchContactPoint(identifier: 1, point: SimulatorPoint(x: 50, y: 100)),
            TouchContactPoint(identifier: 2, point: SimulatorPoint(x: 150, y: 300)),
        ])
    }

    @Test("plan rejects malformed and unterminated gesture lifecycles")
    func rejectsInvalidLifecycle() {
        let id = UUID()
        #expect(throws: GestureReplayError.invalidEvent(0)) {
            try GestureReplayPlan(
                recording: recording(id: id, phases: [.update, .end]),
                targetScreen: SimulatorPointSize(width: 100, height: 200)
            )
        }
        #expect(throws: GestureReplayError.unterminatedGestures) {
            try GestureReplayPlan(
                recording: recording(id: id, phases: [.begin, .update]),
                targetScreen: SimulatorPointSize(width: 100, height: 200)
            )
        }
    }

    @Test("plan rejects invalid timing coordinates and contact topology")
    func rejectsInvalidData() {
        let id = UUID()
        let invalidCoordinate = customRecording(id: id, events: [
            event(id: id, time: 0, phase: .begin, contacts: [
                RecordedTouchContact(id: 1, x: 1.1, y: 0.5),
            ]),
        ])
        #expect(throws: GestureReplayError.invalidEvent(0)) {
            try GestureReplayPlan(
                recording: invalidCoordinate,
                targetScreen: SimulatorPointSize(width: 100, height: 200)
            )
        }

        let decreasingTime = customRecording(id: id, events: [
            event(id: id, time: 1, phase: .begin),
            event(id: id, time: 0.5, phase: .end),
        ])
        #expect(throws: GestureReplayError.invalidEvent(1)) {
            try GestureReplayPlan(
                recording: decreasingTime,
                targetScreen: SimulatorPointSize(width: 100, height: 200)
            )
        }

        let duplicateContacts = customRecording(id: id, events: [
            event(id: id, time: 0, phase: .begin, contacts: [
                RecordedTouchContact(id: 1, x: 0.25, y: 0.25),
                RecordedTouchContact(id: 1, x: 0.75, y: 0.75),
            ]),
        ])
        #expect(throws: GestureReplayError.invalidEvent(0)) {
            try GestureReplayPlan(
                recording: duplicateContacts,
                targetScreen: SimulatorPointSize(width: 100, height: 200)
            )
        }
    }

    @Test("Direct Touch replay supports contacts joining and leaving")
    func directTouchContactChanges() throws {
        let id = UUID()
        let first = RecordedTouchContact(id: 1, x: 0.25, y: 0.25)
        let second = RecordedTouchContact(id: 2, x: 0.75, y: 0.75)
        let recording = GestureRecording(
            name: "Direct Touch Join",
            recordedAt: Date(),
            sourceScreen: RecordingScreen(width: 100, height: 200),
            events: [
                directTouchEvent(id: id, time: 0, phase: .begin, contacts: [first]),
                directTouchEvent(id: id, time: 0.1, phase: .update, contacts: [first, second]),
                directTouchEvent(id: id, time: 0.2, phase: .update, contacts: [second]),
                directTouchEvent(id: id, time: 0.3, phase: .end, contacts: [second]),
            ]
        )

        let plan = try GestureReplayPlan(
            recording: recording,
            targetScreen: SimulatorPointSize(width: 200, height: 400)
        )
        #expect(plan.steps.map { $0.event.snapshot.contacts.count } == [1, 2, 1, 1])
    }

    @Test("engine preserves event timing and playback rate")
    func preservesTiming() async throws {
        let sink = ReplayEngineSink()
        let sleeper = ReplaySleeper()
        let engine = GestureReplayEngine(sink: sink) { duration in
            await sleeper.sleep(duration)
        }

        try engine.play(
            recording(id: UUID()),
            targetScreen: SimulatorPointSize(width: 200, height: 400),
            playbackRate: 2
        )
        await sleeper.waitForCalls(2)
        while engine.state == .replaying { await Task.yield() }

        #expect(await sleeper.recordedDurations() == [.seconds(0.125), .seconds(0.125)])
        #expect(sink.events.map(\.phase) == [.begin, .update, .end])
        #expect(engine.state == .idle)
    }

    @Test("stopping cancels active replay touches exactly once")
    func stopCancels() async throws {
        let sink = ReplayEngineSink()
        let sleeper = BlockingReplaySleeper()
        let engine = GestureReplayEngine(sink: sink) { duration in
            try await sleeper.sleep(duration)
        }

        try engine.play(
            recording(id: UUID()),
            targetScreen: SimulatorPointSize(width: 200, height: 400)
        )
        await sleeper.waitUntilSleeping()
        engine.stop()
        await Task.yield()

        #expect(sink.events.map(\.phase) == [.begin, .cancel])
        #expect(engine.state == .idle)
    }

    @Test("empty recordings complete without emitting input")
    func emptyRecording() async throws {
        let sink = ReplayEngineSink()
        let engine = GestureReplayEngine(sink: sink)
        var outcome: GestureReplayOutcome?
        let recording = GestureRecording(
            name: "Empty",
            recordedAt: Date(),
            sourceScreen: RecordingScreen(width: 100, height: 200),
            events: []
        )

        try engine.play(
            recording,
            targetScreen: SimulatorPointSize(width: 200, height: 400),
            completion: { outcome = $0 }
        )
        while engine.state == .replaying { await Task.yield() }

        #expect(outcome == .completed)
        #expect(sink.events.isEmpty)
    }

    private func recording(
        id: UUID,
        phases: [RecordedTouchPhase] = [.begin, .update, .end]
    ) -> GestureRecording {
        let times: [TimeInterval] = [0, 0.25, 0.5]
        return GestureRecording(
            name: "Two Finger",
            recordedAt: Date(timeIntervalSince1970: 1_000),
            sourceScreen: RecordingScreen(width: 400, height: 800),
            events: phases.enumerated().map { index, phase in
                RecordedTouchEvent(
                    time: times[index],
                    gestureID: id,
                    phase: phase,
                    source: .rawTrackpad,
                    intent: .directTouch,
                    anchorX: 0.5,
                    anchorY: 0.5,
                    contacts: [
                        RecordedTouchContact(id: 1, x: 0.25, y: 0.25),
                        RecordedTouchContact(id: 2, x: 0.75, y: 0.75),
                    ]
                )
            }
        )
    }

    private func customRecording(
        id: UUID,
        events: [RecordedTouchEvent]
    ) -> GestureRecording {
        GestureRecording(
            name: "Invalid \(id)",
            recordedAt: Date(),
            sourceScreen: RecordingScreen(width: 100, height: 200),
            events: events
        )
    }

    private func event(
        id: UUID,
        time: TimeInterval,
        phase: RecordedTouchPhase,
        contacts: [RecordedTouchContact] = [
            RecordedTouchContact(id: 1, x: 0.25, y: 0.25),
        ]
    ) -> RecordedTouchEvent {
        RecordedTouchEvent(
            time: time,
            gestureID: id,
            phase: phase,
            source: .mouse,
            intent: .point,
            anchorX: 0.5,
            anchorY: 0.5,
            contacts: contacts
        )
    }

    private func directTouchEvent(
        id: UUID,
        time: TimeInterval,
        phase: RecordedTouchPhase,
        contacts: [RecordedTouchContact]
    ) -> RecordedTouchEvent {
        RecordedTouchEvent(
            time: time,
            gestureID: id,
            phase: phase,
            source: .rawTrackpad,
            intent: .directTouch,
            anchorX: 0.5,
            anchorY: 0.5,
            contacts: contacts
        )
    }
}

private final class ReplayEngineSink: TouchSink {
    private(set) var events: [TouchLifecycleEvent] = []
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private actor ReplaySleeper {
    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) {
        durations.append(duration)
    }

    func waitForCalls(_ count: Int) async {
        while durations.count < count { await Task.yield() }
    }

    func recordedDurations() -> [Duration] { durations }
}

private actor BlockingReplaySleeper {
    private var isSleeping = false

    func sleep(_ duration: Duration) async throws {
        isSleeping = true
        try await Task.sleep(for: duration)
    }

    func waitUntilSleeping() async {
        while !isSleeping { await Task.yield() }
    }
}

private extension TouchLifecycleEvent {
    var snapshot: TouchTransactionSnapshot {
        switch self {
        case let .begin(snapshot), let .update(snapshot), let .end(snapshot), let .cancel(snapshot):
            snapshot
        }
    }

    var phase: RecordedTouchPhase {
        switch self {
        case .begin: .begin
        case .update: .update
        case .end: .end
        case .cancel: .cancel
        }
    }
}
