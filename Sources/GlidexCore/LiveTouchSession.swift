import CoreGraphics
import Dispatch
import Foundation

public final class LiveTouchSession: @unchecked Sendable {
    private let hidClient: SimulatorHIDClient
    private let metrics: ScreenMetrics
    private let logger: Logger
    private let dumpsHIDMessages: Bool
    private let logsTouchEvents: Bool
    private let queue = DispatchQueue(label: "glidex.live-touch-session")

    private var isActive = false
    private var currentPoint: CGPoint?
    public var onError: (@Sendable (String) -> Void)?

    init(hidClient: SimulatorHIDClient, metrics: ScreenMetrics, logger: Logger, dumpsHIDMessages: Bool) {
        self.hidClient = hidClient
        self.metrics = metrics
        self.logger = logger
        self.dumpsHIDMessages = dumpsHIDMessages
        self.logsTouchEvents = ProcessInfo.processInfo.environment["GLIDEX_LOG_TOUCH_EVENTS"] == "1"
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

    public func end(at point: CGPoint? = nil, delay: TimeInterval = 0) {
        enqueue { state in
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
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
            logTouchEventIfEnabled(description: description, direction: direction, point: point)
            logMessageIfEnabled(message)
            hidClient.send(message: message, waitForCompletion: false) { [weak self] error in
                guard let error else { return }
                self?.reportFailure(description: description, message: error)
            }
        } catch {
            reportFailure(description: description, message: String(describing: error))
        }
    }

    private func reportFailure(description: String, message: String) {
        logger.error("\(description) failed: \(message)")
        onError?(message)
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

    private func logTouchEventIfEnabled(description: String, direction: TouchDirection, point: CGPoint) {
        guard logsTouchEvents else { return }
        logger.info("\(description) direction=\(direction) point=(\(point.x), \(point.y))")
    }
}
