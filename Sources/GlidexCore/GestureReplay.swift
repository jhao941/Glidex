import Foundation

public struct GestureReplayStep: Equatable, Sendable {
    public let time: TimeInterval
    public let event: TouchLifecycleEvent

    public init(time: TimeInterval, event: TouchLifecycleEvent) {
        self.time = time
        self.event = event
    }
}

public struct GestureReplayPlan: Equatable, Sendable {
    public let steps: [GestureReplayStep]

    public init(
        recording: GestureRecording,
        targetScreen: SimulatorPointSize,
        gestureIDProvider: () -> UUID = UUID.init
    ) throws {
        guard targetScreen.width.isFinite, targetScreen.height.isFinite,
              targetScreen.width > 0, targetScreen.height > 0 else {
            throw GestureReplayError.invalidTargetScreen
        }

        var gestureIDs: [UUID: UUID] = [:]
        var activeSnapshots: [UUID: TouchTransactionSnapshot] = [:]
        var steps: [GestureReplayStep] = []
        var previousTime: TimeInterval = 0

        for (index, recordedEvent) in recording.events.enumerated() {
            guard recordedEvent.time.isFinite,
                  recordedEvent.time >= previousTime,
                  recordedEvent.anchorX.isReplayNormalized,
                  recordedEvent.anchorY.isReplayNormalized,
                  recordedEvent.contacts.allSatisfy({
                      $0.x.isReplayNormalized && $0.y.isReplayNormalized
                  }),
                  Set(recordedEvent.contacts.map(\.id)).count == recordedEvent.contacts.count else {
                throw GestureReplayError.invalidEvent(index)
            }
            let replayGestureID: UUID
            switch recordedEvent.phase {
            case .begin:
                guard activeSnapshots[recordedEvent.gestureID] == nil,
                      Self.supportedContactCount(
                          recordedEvent.contacts.count,
                          intent: recordedEvent.intent
                      ) else {
                    throw GestureReplayError.invalidEvent(index)
                }
                replayGestureID = gestureIDProvider()
                gestureIDs[recordedEvent.gestureID] = replayGestureID
            case .update, .end, .cancel:
                guard let mappedID = gestureIDs[recordedEvent.gestureID],
                      let active = activeSnapshots[recordedEvent.gestureID],
                      active.source == recordedEvent.source,
                      active.intent == recordedEvent.intent,
                      Self.supportedContactCount(
                          recordedEvent.contacts.count,
                          intent: recordedEvent.intent
                      ),
                      recordedEvent.intent == .directTouch
                        || recordedEvent.contacts.count == active.contacts.count else {
                    throw GestureReplayError.invalidEvent(index)
                }
                replayGestureID = mappedID
            }

            let snapshot = TouchTransactionSnapshot(
                gestureID: replayGestureID,
                source: recordedEvent.source,
                intent: recordedEvent.intent,
                anchor: SimulatorPoint(
                    x: CGFloat(recordedEvent.anchorX) * targetScreen.width,
                    y: CGFloat(recordedEvent.anchorY) * targetScreen.height
                ),
                contacts: recordedEvent.contacts.map {
                    TouchContactPoint(
                        identifier: $0.id,
                        point: SimulatorPoint(
                            x: CGFloat($0.x) * targetScreen.width,
                            y: CGFloat($0.y) * targetScreen.height
                        )
                    )
                }
            )
            let event: TouchLifecycleEvent
            switch recordedEvent.phase {
            case .begin:
                event = .begin(snapshot)
                activeSnapshots[recordedEvent.gestureID] = snapshot
            case .update:
                event = .update(snapshot)
                activeSnapshots[recordedEvent.gestureID] = snapshot
            case .end:
                event = .end(snapshot)
                activeSnapshots[recordedEvent.gestureID] = nil
                gestureIDs[recordedEvent.gestureID] = nil
            case .cancel:
                event = .cancel(snapshot)
                activeSnapshots[recordedEvent.gestureID] = nil
                gestureIDs[recordedEvent.gestureID] = nil
            }
            steps.append(GestureReplayStep(time: recordedEvent.time, event: event))
            previousTime = recordedEvent.time
        }

        guard activeSnapshots.isEmpty else {
            throw GestureReplayError.unterminatedGestures
        }
        self.steps = steps
    }

    private static func supportedContactCount(_ count: Int, intent: GestureIntent) -> Bool {
        intent == .directTouch ? (1...5).contains(count) : (1...2).contains(count)
    }
}

public enum GestureReplayOutcome: Equatable, Sendable {
    case completed
    case stopped
    case failed(String)
}

private extension Double {
    var isReplayNormalized: Bool { isFinite && self >= 0 && self <= 1 }
}

public enum GestureReplayError: Error, Equatable, Sendable {
    case alreadyReplaying
    case invalidPlaybackRate
    case invalidTargetScreen
    case invalidEvent(Int)
    case unterminatedGestures
}

@MainActor
public final class GestureReplayEngine {
    public enum State: Equatable, Sendable {
        case idle
        case replaying
    }

    public typealias Sleeper = @Sendable (Duration) async throws -> Void
    public typealias Completion = (GestureReplayOutcome) -> Void

    private let sink: TouchSink
    private let sleeper: Sleeper
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private var activeSnapshots: [UUID: TouchTransactionSnapshot] = [:]
    private var completion: Completion?

    public var state: State { generation == nil ? .idle : .replaying }

    public init(
        sink: TouchSink,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.sink = sink
        self.sleeper = sleeper
    }

    public func play(
        _ recording: GestureRecording,
        targetScreen: SimulatorPointSize,
        playbackRate: Double = 1,
        completion: Completion? = nil
    ) throws {
        guard generation == nil else { throw GestureReplayError.alreadyReplaying }
        guard playbackRate.isFinite, playbackRate > 0 else {
            throw GestureReplayError.invalidPlaybackRate
        }
        let plan = try GestureReplayPlan(recording: recording, targetScreen: targetScreen)
        let generation = UUID()
        self.generation = generation
        self.completion = completion
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var previousTime: TimeInterval = 0
                for step in plan.steps {
                    let delay = max(0, step.time - previousTime) / playbackRate
                    if delay > 0 {
                        try await sleeper(.seconds(delay))
                    }
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    self.deliver(step.event)
                    previousTime = step.time
                }
                self.finish(generation: generation, outcome: .completed)
            } catch is CancellationError {
                self.finish(generation: generation, outcome: .stopped)
            } catch {
                self.finish(generation: generation, outcome: .failed(String(describing: error)))
            }
        }
    }

    public func stop() {
        guard let generation else { return }
        task?.cancel()
        cancelActiveTouches()
        finish(generation: generation, outcome: .stopped)
    }

    private func deliver(_ event: TouchLifecycleEvent) {
        switch event {
        case let .begin(snapshot), let .update(snapshot):
            activeSnapshots[snapshot.gestureID] = snapshot
        case let .end(snapshot), let .cancel(snapshot):
            activeSnapshots[snapshot.gestureID] = nil
        }
        sink.receive(event)
    }

    private func cancelActiveTouches() {
        for snapshot in activeSnapshots.values.sorted(by: { $0.gestureID.uuidString < $1.gestureID.uuidString }) {
            sink.receive(.cancel(snapshot))
        }
        activeSnapshots.removeAll()
    }

    private func finish(generation: UUID, outcome: GestureReplayOutcome) {
        guard self.generation == generation else { return }
        if outcome != .completed {
            cancelActiveTouches()
        }
        task = nil
        self.generation = nil
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }
}
