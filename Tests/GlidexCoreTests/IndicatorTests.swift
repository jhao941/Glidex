import Foundation
import GlidexCore
import Testing

@Suite("Indicators")
struct IndicatorTests {
    @Test("observing sink reports begin update end and cancel without changing downstream")
    func observingSinkLifecycle() {
        let downstream = IndicatorRecordingSink()
        var observed: [TouchLifecycleEvent] = []
        let sink = TouchObservingSink(downstream: downstream) { observed.append($0) }
        let transaction = TouchTransaction(
            source: .rawTrackpad,
            intent: .pinch,
            anchor: SimulatorPoint(x: 200, y: 400),
            sink: sink
        )
        let twoContacts = [
            TouchContactPoint(identifier: 0, point: SimulatorPoint(x: 160, y: 400)),
            TouchContactPoint(identifier: 1, point: SimulatorPoint(x: 240, y: 400)),
        ]
        transaction.begin(contacts: twoContacts)
        transaction.update(contacts: [
            TouchContactPoint(identifier: 0, point: SimulatorPoint(x: 150, y: 400)),
            TouchContactPoint(identifier: 1, point: SimulatorPoint(x: 250, y: 400)),
        ])
        transaction.end()

        #expect(observed == downstream.events)
        #expect(observed.count == 3)
        #expect(observed.first?.contacts.count == 2)
        #expect(ActiveTouchIndicatorLifecycle.contacts(for: observed[0]).count == 2)
        #expect(ActiveTouchIndicatorLifecycle.contacts(for: observed[1]).count == 2)
        #expect(ActiveTouchIndicatorLifecycle.contacts(for: observed[2]).isEmpty)

        let cancelled = TouchTransaction(
            source: .mouse,
            intent: .point,
            anchor: SimulatorPoint(x: 20, y: 30),
            sink: sink
        )
        cancelled.begin(contacts: [TouchContactPoint(identifier: 0, point: SimulatorPoint(x: 20, y: 30))])
        cancelled.cancel()
        #expect(observed.last?.isCancel == true)
        #expect(ActiveTouchIndicatorLifecycle.contacts(for: observed.last!).isEmpty)
    }

    @Test("anchor and active touch preferences are independent")
    @MainActor
    func independentPreferences() {
        let state = GlidexAppState()
        state.setShowsAnchorIndicator(false)
        state.setShowsActiveTouches(true)
        state.setAnchorIndicator(.fixed(SimulatorPoint(x: 30, y: 40)))
        state.setActiveTouches([TouchContactPoint(identifier: 0, point: SimulatorPoint(x: 10, y: 20))])

        let presentation = OverlayPresentation(snapshot: state.snapshot)
        #expect(!presentation.showsAnchorIndicator)
        #expect(presentation.showsActiveTouches)
        #expect(presentation.anchorIndicator == .fixed(SimulatorPoint(x: 30, y: 40)))
        #expect(presentation.activeTouches.count == 1)

        state.setShowsActiveTouches(false)
        #expect(state.snapshot.activeTouches.isEmpty)
    }

    @Test("device changes clear and reinitialize the fixed anchor")
    @MainActor
    func mapperRefreshesAnchor() {
        let sink = IndicatorRecordingSink()
        let coordinator = GestureCoordinator(
            mapper: CoordinateMapper(captureRect: .zero, simulatorSize: SimulatorPointSize(width: 100, height: 200)),
            sink: sink,
            logger: Logger()
        )
        coordinator.setMode(.point)
        coordinator.updateMapper(CoordinateMapper(
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 200),
            simulatorSize: SimulatorPointSize(width: 100, height: 200)
        ))
        #expect(coordinator.virtualFingerPoint == SimulatorPoint(x: 50, y: 100))

        coordinator.prepareForDeviceChange()
        #expect(coordinator.virtualFingerPoint == nil)
        coordinator.updateMapper(CoordinateMapper(
            captureRect: CGRect(x: 0, y: 0, width: 300, height: 600),
            simulatorSize: SimulatorPointSize(width: 300, height: 600)
        ))
        #expect(coordinator.virtualFingerPoint == SimulatorPoint(x: 150, y: 300))
    }
}

private final class IndicatorRecordingSink: TouchSink {
    var events: [TouchLifecycleEvent] = []
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private extension TouchLifecycleEvent {
    var contacts: [TouchContactPoint] {
        switch self {
        case let .begin(snapshot), let .update(snapshot), let .end(snapshot), let .cancel(snapshot): snapshot.contacts
        }
    }
    var isCancel: Bool { if case .cancel = self { true } else { false } }
}
