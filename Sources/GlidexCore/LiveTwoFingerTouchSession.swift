import CoreGraphics
import Dispatch
import Foundation

public final class LiveTwoFingerTouchSession: @unchecked Sendable {
    private let hidClient: SimulatorHIDClient
    private let metrics: ScreenMetrics
    private let logger: Logger
    private let dumpsHIDMessages: Bool
    private let logsTouchEvents: Bool
    private let queue = DispatchQueue(label: "glidex.live-two-finger-touch-session")

    private var isActive = false
    private var currentFingers: (CGPoint, CGPoint)?
    public var onError: (@Sendable (String) -> Void)?

    init(hidClient: SimulatorHIDClient, metrics: ScreenMetrics, logger: Logger, dumpsHIDMessages: Bool) {
        self.hidClient = hidClient
        self.metrics = metrics
        self.logger = logger
        self.dumpsHIDMessages = dumpsHIDMessages
        self.logsTouchEvents = ProcessInfo.processInfo.environment["GLIDEX_LOG_TOUCH_EVENTS"] == "1"
    }

    public func begin(finger1: CGPoint, finger2: CGPoint) {
        enqueue { state in
            guard !state.isActive else {
                state.logger.warn("live two-finger begin ignored because a touch is already active")
                return
            }
            state.isActive = true
            state.currentFingers = (state.clamped(finger1), state.clamped(finger2))
            state.sendTouch(fingers: state.currentFingers!, direction: .down, description: "live two-finger begin")
        }
    }

    public func update(finger1: CGPoint, finger2: CGPoint, delay: TimeInterval = 0) {
        enqueue { state in
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            guard state.isActive else {
                state.logger.warn("live two-finger update ignored because no touch is active")
                return
            }
            let fingers = (state.clamped(finger1), state.clamped(finger2))
            state.currentFingers = fingers
            state.sendTouch(fingers: fingers, direction: .down, description: "live two-finger update")
        }
    }

    public func end(finger1: CGPoint? = nil, finger2: CGPoint? = nil, delay: TimeInterval = 0) {
        enqueue { state in
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            guard state.isActive else { return }
            let fingers = state.endingFingers(finger1: finger1, finger2: finger2)
            if let fingers {
                state.sendTouch(fingers: fingers, direction: .up, description: "live two-finger end")
            }
            state.currentFingers = nil
            state.isActive = false
        }
    }

    public func cancel() {
        end()
    }

    private func enqueue(_ work: @escaping @Sendable (LiveTwoFingerTouchSession) -> Void) {
        queue.async {
            work(self)
        }
    }

    private func endingFingers(finger1: CGPoint?, finger2: CGPoint?) -> (CGPoint, CGPoint)? {
        if let finger1, let finger2 {
            return (clamped(finger1), clamped(finger2))
        }
        return currentFingers
    }

    private func sendTouch(fingers: (CGPoint, CGPoint), direction: TouchDirection, description: String) {
        do {
            let message = try TouchMessageBuilder.twoFingerTouch(
                finger1: fingers.0,
                finger2: fingers.1,
                screenPointSize: metrics.pointSize,
                direction: direction
            )
            logTouchEventIfEnabled(description: description, direction: direction, fingers: fingers)
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

    private func logTouchEventIfEnabled(description: String, direction: TouchDirection, fingers: (CGPoint, CGPoint)) {
        guard logsTouchEvents else { return }
        logger.info("\(description) direction=\(direction) finger1=(\(fingers.0.x), \(fingers.0.y)) finger2=(\(fingers.1.x), \(fingers.1.y))")
    }
}
