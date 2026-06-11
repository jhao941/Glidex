import Foundation
import GlidexCore
import Testing

@Suite("Anchor lock")
@MainActor
struct AnchorLockTests {
    @Test("unlocked Point edits the anchor without injecting")
    func unlockedPointEditsOnly() {
        let sink = AnchorRecordingSink()
        let coordinator = makeCoordinator(sink: sink)
        coordinator.setMode(.point)

        coordinator.beginMouse(at: CapturePoint(x: 40, y: 700))
        coordinator.updateMouse(at: CapturePoint(x: 80, y: 674))
        coordinator.endMouse(at: CapturePoint(x: 80, y: 674))

        #expect(sink.events.isEmpty)
        #expect(coordinator.virtualFingerPoint == SimulatorPoint(x: 80, y: 200))
    }

    @Test("locked Point restores mouse tap and drag injection")
    func lockedPointInjectsMouse() {
        let sink = AnchorRecordingSink()
        let coordinator = makeCoordinator(sink: sink)
        coordinator.setMode(.point)
        coordinator.updatePointer(CapturePoint(x: 60, y: 774))
        coordinator.setAnchorLocked(true)

        coordinator.beginMouse(at: CapturePoint(x: 100, y: 674))
        coordinator.endMouse(at: CapturePoint(x: 100, y: 674))

        #expect(sink.events.filter(\.isBegin).count == 1)
        #expect(sink.events.filter(\.isEnd).count == 1)
        #expect(sink.events.first?.snapshot?.anchor == SimulatorPoint(x: 100, y: 200))
        #expect(abs((coordinator.virtualFingerPoint?.x ?? 0) - 60) < 0.001)
        #expect(abs((coordinator.virtualFingerPoint?.y ?? 0) - 100) < 0.001)
    }

    @Test("locked Edge restores mouse tap injection without moving its anchor")
    func lockedEdgeInjectsMouse() {
        let sink = AnchorRecordingSink()
        let coordinator = makeCoordinator(sink: sink)
        coordinator.setMode(.edge)
        coordinator.updatePointer(CapturePoint(x: 2, y: 437))
        coordinator.setAnchorLocked(true)

        coordinator.beginMouse(at: CapturePoint(x: 200, y: 600))
        coordinator.endMouse(at: CapturePoint(x: 200, y: 600))

        #expect(sink.events.filter(\.isBegin).count == 1)
        #expect(sink.events.filter(\.isEnd).count == 1)
        #expect(abs((coordinator.virtualFingerPoint?.x ?? 0) - 2) < 0.001)
        #expect(abs((coordinator.virtualFingerPoint?.y ?? 0) - 437) < 0.001)
    }

    @Test("changing anchor lock cancels an active transaction")
    func lockChangeCancels() throws {
        struct Fixture: Decodable { let frames: [RawTouchFrame] }
        let url = try #require(Bundle.module.url(forResource: "swipe-right", withExtension: "json"))
        let frames = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).frames
        let sink = AnchorRecordingSink()
        let coordinator = makeCoordinator(sink: sink)
        coordinator.setMode(.point)
        for frame in frames {
            coordinator.handleRawFrame(frame)
            if sink.events.contains(where: \.isBegin) { break }
        }

        coordinator.setAnchorLocked(true)

        #expect(sink.events.filter(\.isCancel).count == 1)
        #expect(sink.events.filter(\.isEnd).isEmpty)
    }

    @Test("runtime lock state is independent from the input mode")
    func appStateLock() {
        let state = GlidexAppState()
        state.setInputMode(.edge)
        #expect(state.snapshot.anchorLockState == .unlocked)
        state.setAnchorLocked(true)
        #expect(state.snapshot.anchorLockState == .locked)
        #expect(state.snapshot.preferences.inputMode == .edge)
        state.resetAnchorLockForAttachment()
        #expect(state.snapshot.anchorLockState == .unlocked)
        #expect(state.snapshot.preferences.prefersAnchorLocked)
        state.setInputMode(.navigate)
        #expect(state.snapshot.anchorLockState == .unavailable)
    }

    private func makeCoordinator(sink: AnchorRecordingSink) -> GestureCoordinator {
        GestureCoordinator(
            mapper: CoordinateMapper(
                captureRect: CGRect(x: 0, y: 0, width: 402, height: 874),
                simulatorSize: SimulatorPointSize(width: 402, height: 874)
            ),
            sink: sink,
            logger: Logger()
        )
    }
}

private final class AnchorRecordingSink: TouchSink {
    var events: [TouchLifecycleEvent] = []
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private extension TouchLifecycleEvent {
    var snapshot: TouchTransactionSnapshot? {
        switch self {
        case let .begin(snapshot), let .update(snapshot), let .end(snapshot), let .cancel(snapshot): snapshot
        }
    }
    var isBegin: Bool { if case .begin = self { true } else { false } }
    var isEnd: Bool { if case .end = self { true } else { false } }
    var isCancel: Bool { if case .cancel = self { true } else { false } }
}
