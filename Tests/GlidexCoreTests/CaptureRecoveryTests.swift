import Foundation
import GlidexCore
import Testing

@Suite("Capture recovery")
@MainActor
struct CaptureRecoveryTests {
    @Test("Simulator disappearance cancels one active transaction exactly once")
    func disappearanceCancelsOnce() throws {
        struct Fixture: Decodable { let frames: [RawTouchFrame] }
        let url = try #require(Bundle.module.url(forResource: "swipe-right", withExtension: "json"))
        let frames = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).frames
        let sink = RecoveryRecordingSink()
        let coordinator = GestureCoordinator(
            mapper: CoordinateMapper(
                captureRect: CGRect(x: 0, y: 0, width: 402, height: 874),
                simulatorSize: SimulatorPointSize(width: 402, height: 874)
            ),
            sink: sink,
            logger: Logger()
        )

        for frame in frames {
            coordinator.handleRawFrame(frame)
            if sink.events.contains(where: \.isBegin) { break }
        }
        coordinator.cancelAll(reason: "Simulator disappeared")
        coordinator.cancelAll(reason: "duplicate disappearance notification")

        #expect(sink.events.filter(\.isBegin).count == 1)
        #expect(sink.events.filter(\.isCancel).count == 1)
        #expect(sink.events.filter(\.isEnd).isEmpty)
    }

    @Test("reconnect preserves persistent Enabled and mode settings")
    func reconnectPreservesPreferences() {
        let state = GlidexAppState(snapshot: GlidexAppSnapshot(
            preferences: GlidexPreferenceValues(
                isEnabled: true,
                inputMode: .edge
            ),
            status: .active,
            target: target(name: "Old", udid: "A")
        ))

        state.transition(to: .waiting("Simulator restarted"))
        state.transition(to: .active, target: target(name: "New", udid: "B"))

        #expect(state.snapshot.preferences.isEnabled)
        #expect(state.snapshot.preferences.inputMode == .edge)
        #expect(state.snapshot.target?.udid == "B")
        #expect(state.snapshot.acceptsInput)
    }

    @Test("Waiting and Error states cannot deliver input to an old device")
    func inactiveStatesRejectInput() {
        let waiting = GlidexAppSnapshot(status: .waiting("Simulator closed"))
        let failed = GlidexAppSnapshot(status: .error(.hidInitialization("test")))

        #expect(!waiting.acceptsInput)
        #expect(!failed.acceptsInput)
    }

    private func target(name: String, udid: String) -> SimulatorTarget {
        SimulatorTarget(
            name: name,
            udid: udid,
            runtime: "iOS 26.0",
            deviceType: name,
            pointSize: SimulatorPointSize(width: 402, height: 874)
        )
    }
}

private final class RecoveryRecordingSink: TouchSink {
    var events: [TouchLifecycleEvent] = []
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private extension TouchLifecycleEvent {
    var isBegin: Bool { if case .begin = self { true } else { false } }
    var isEnd: Bool { if case .end = self { true } else { false } }
    var isCancel: Bool { if case .cancel = self { true } else { false } }
}
