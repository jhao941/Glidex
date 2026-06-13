import CoreGraphics
import Foundation

public final class GestureRecorder {
    public enum State: Equatable, Sendable {
        case idle
        case recording
    }

    private struct Session {
        let name: String
        let recordedAt: Date
        let sourceScreen: RecordingScreen
        let startedAt: TimeInterval
        var lastEventTime: TimeInterval = 0
        var trackedGestureIDs: Set<UUID> = []
        var latestSnapshots: [UUID: TouchTransactionSnapshot] = [:]
        var events: [RecordedTouchEvent] = []
    }

    private let timeProvider: () -> TimeInterval
    private var session: Session?

    public var state: State { session == nil ? .idle : .recording }

    public init(timeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.timeProvider = timeProvider
    }

    public func start(
        name: String,
        sourceScreen: SimulatorPointSize,
        recordedAt: Date = Date()
    ) throws {
        guard session == nil else { throw GestureRecordingError.alreadyRecording }
        let screen = RecordingScreen(sourceScreen)
        guard screen.isValid else { throw GestureRecordingError.invalidSourceScreen }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session = Session(
            name: trimmedName.isEmpty ? "Untitled Recording" : trimmedName,
            recordedAt: recordedAt,
            sourceScreen: screen,
            startedAt: timeProvider()
        )
    }

    public func record(_ event: TouchLifecycleEvent) {
        guard var session else { return }
        let phase = phaseAndSnapshot(for: event)
        let gestureID = phase.snapshot.gestureID

        if phase.phase == .begin {
            session.trackedGestureIDs.insert(gestureID)
        } else if !session.trackedGestureIDs.contains(gestureID) {
            return
        }

        let elapsed = max(session.lastEventTime, max(0, timeProvider() - session.startedAt))
        session.lastEventTime = elapsed
        session.events.append(recordedEvent(
            phase: phase.phase,
            snapshot: phase.snapshot,
            time: elapsed,
            sourceScreen: session.sourceScreen
        ))
        session.latestSnapshots[gestureID] = phase.snapshot
        if phase.phase == .end || phase.phase == .cancel {
            session.trackedGestureIDs.remove(gestureID)
            session.latestSnapshots[gestureID] = nil
        }
        self.session = session
    }

    public func stop() -> GestureRecording? {
        guard var session else { return nil }
        let stopTime = max(session.lastEventTime, max(0, timeProvider() - session.startedAt))
        for gestureID in session.trackedGestureIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let snapshot = session.latestSnapshots[gestureID] else { continue }
            session.events.append(recordedEvent(
                phase: .cancel,
                snapshot: snapshot,
                time: stopTime,
                sourceScreen: session.sourceScreen
            ))
        }
        self.session = nil
        return GestureRecording(
            name: session.name,
            recordedAt: session.recordedAt,
            sourceScreen: session.sourceScreen,
            events: session.events
        )
    }

    public func discard() {
        session = nil
    }

    private func phaseAndSnapshot(
        for event: TouchLifecycleEvent
    ) -> (phase: RecordedTouchPhase, snapshot: TouchTransactionSnapshot) {
        switch event {
        case let .begin(snapshot): (.begin, snapshot)
        case let .update(snapshot): (.update, snapshot)
        case let .end(snapshot): (.end, snapshot)
        case let .cancel(snapshot): (.cancel, snapshot)
        }
    }

    private func recordedEvent(
        phase: RecordedTouchPhase,
        snapshot: TouchTransactionSnapshot,
        time: TimeInterval,
        sourceScreen: RecordingScreen
    ) -> RecordedTouchEvent {
        RecordedTouchEvent(
            time: time,
            gestureID: snapshot.gestureID,
            phase: phase,
            source: snapshot.source,
            intent: snapshot.intent,
            anchorX: normalized(snapshot.anchor.x, extent: sourceScreen.width),
            anchorY: normalized(snapshot.anchor.y, extent: sourceScreen.height),
            contacts: snapshot.contacts.sorted { $0.identifier < $1.identifier }.map { contact in
                RecordedTouchContact(
                    id: contact.identifier,
                    x: normalized(contact.point.x, extent: sourceScreen.width),
                    y: normalized(contact.point.y, extent: sourceScreen.height)
                )
            }
        )
    }

    private func normalized(_ value: CGFloat, extent: Double) -> Double {
        min(max(Double(value) / extent, 0), 1)
    }
}
