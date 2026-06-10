import CoreGraphics
import Foundation

public enum MouseGestureAction: Equatable, Sendable {
    case beginDrag(start: SimulatorPoint, current: SimulatorPoint)
    case updateDrag(SimulatorPoint)
    case endDrag(SimulatorPoint)
    case tap(SimulatorPoint)
    case cancelDrag
}

public struct MouseGestureStateMachine: Sendable {
    private enum State: Sendable {
        case idle
        case pending(startCapture: CapturePoint, startSimulator: SimulatorPoint)
        case dragging(startSimulator: SimulatorPoint, current: SimulatorPoint)
    }

    private let threshold: CGFloat
    private var state: State = .idle

    public init(threshold: CGFloat = InputTuning.stable.mouseDragThreshold) {
        self.threshold = threshold
    }

    public mutating func mouseDown(capture: CapturePoint, simulator: SimulatorPoint) -> [MouseGestureAction] {
        let cancellation = cancel()
        state = .pending(startCapture: capture, startSimulator: simulator)
        return cancellation.map { [$0] } ?? []
    }

    public mutating func mouseDragged(capture: CapturePoint, simulator: SimulatorPoint) -> [MouseGestureAction] {
        switch state {
        case .idle:
            return []
        case let .pending(startCapture, startSimulator):
            guard startCapture.distance(to: capture) >= threshold else { return [] }
            state = .dragging(startSimulator: startSimulator, current: simulator)
            return [.beginDrag(start: startSimulator, current: simulator)]
        case let .dragging(startSimulator, current):
            guard current != simulator else { return [] }
            state = .dragging(startSimulator: startSimulator, current: simulator)
            return [.updateDrag(simulator)]
        }
    }

    public mutating func mouseUp(capture: CapturePoint, simulator: SimulatorPoint) -> [MouseGestureAction] {
        switch state {
        case .idle:
            return []
        case let .pending(startCapture, startSimulator):
            state = .idle
            guard startCapture.distance(to: capture) < threshold else {
                return [.beginDrag(start: startSimulator, current: simulator), .endDrag(simulator)]
            }
            return [.tap(startSimulator)]
        case .dragging:
            state = .idle
            return [.endDrag(simulator)]
        }
    }

    public mutating func cancel() -> MouseGestureAction? {
        defer { state = .idle }
        if case .dragging = state { return .cancelDrag }
        return nil
    }
}

private extension CapturePoint {
    func distance(to other: CapturePoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
