import CoreGraphics
import Dispatch
import Foundation

public final class LiveTouchSession: @unchecked Sendable {
    private let hidClient: SimulatorHIDClient
    private let metrics: ScreenMetrics
    private let logger: Logger
    private let dumpsHIDMessages: Bool
    private let queue = DispatchQueue(label: "glidex.live-touch-session")

    private var isActive = false
    private var currentPoint: CGPoint?

    init(hidClient: SimulatorHIDClient, metrics: ScreenMetrics, logger: Logger, dumpsHIDMessages: Bool) {
        self.hidClient = hidClient
        self.metrics = metrics
        self.logger = logger
        self.dumpsHIDMessages = dumpsHIDMessages
    }

    public func begin(at point: CGPoint) {
        enqueue { state in
            guard !state.isActive else {
                state.logger.warn("live touch begin ignored because a touch is already active")
                return
            }
            state.isActive = true
            state.currentPoint = state.clamped(point)
            state.sendTouch(at: state.currentPoint!, direction: .down, description: "live touch begin")
        }
    }

    public func update(to point: CGPoint) {
        enqueue { state in
            guard state.isActive else {
                state.logger.warn("live touch update ignored because no touch is active")
                return
            }
            let nextPoint = state.clamped(point)
            guard state.currentPoint != nextPoint else { return }
            state.currentPoint = nextPoint
            state.sendTouch(at: nextPoint, direction: .down, description: "live touch update")
        }
    }

    public func end(at point: CGPoint? = nil) {
        enqueue { state in
            guard state.isActive else { return }
            let endPoint = point.map(state.clamped) ?? state.currentPoint
            if let endPoint {
                state.sendTouch(at: endPoint, direction: .up, description: "live touch end")
            }
            state.currentPoint = nil
            state.isActive = false
        }
    }

    public func cancel() {
        end()
    }

    public func waitUntilIdle() {
        queue.sync {}
    }

    private func enqueue(_ work: @escaping @Sendable (LiveTouchSession) -> Void) {
        queue.async {
            work(self)
        }
    }

    private func sendTouch(at point: CGPoint, direction: TouchDirection, description: String) {
        do {
            let message = try TouchMessageBuilder.singleTouch(
                point: point,
                screenPointSize: metrics.pointSize,
                direction: direction
            )
            logger.info("\(description) direction=\(direction) point=(\(point.x), \(point.y))")
            logMessageIfEnabled(message)
            hidClient.send(message: message)
        } catch {
            logger.error("\(description) failed: \(error)")
        }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), metrics.pointSize.width),
            y: min(max(point.y, 0), metrics.pointSize.height)
        )
    }

    private func logMessageIfEnabled(_ message: UnsafeMutableRawPointer) {
        guard dumpsHIDMessages else { return }
        logger.info("message \(TouchMessageBuilder.describe(message))")
    }
}
