import CoreGraphics
import Dispatch
import Foundation

public final class LiveDirectTouchSession: @unchecked Sendable {
    private let hidClient: SimulatorHIDClient
    private let metrics: ScreenMetrics
    private let logger: Logger
    private let dumpsHIDMessages: Bool
    private let logsTouchEvents: Bool
    private let queue = DispatchQueue(label: "glidex.live-direct-touch-session")

    private var currentContacts: [TouchContactPoint] = []
    public var onError: (@Sendable (String) -> Void)?

    init(hidClient: SimulatorHIDClient, metrics: ScreenMetrics, logger: Logger, dumpsHIDMessages: Bool) {
        self.hidClient = hidClient
        self.metrics = metrics
        self.logger = logger
        self.dumpsHIDMessages = dumpsHIDMessages
        self.logsTouchEvents = ProcessInfo.processInfo.environment["GLIDEX_LOG_TOUCH_EVENTS"] == "1"
    }

    public func begin(contacts: [TouchContactPoint]) {
        enqueue { state in
            guard state.currentContacts.isEmpty else {
                state.logger.warn("live Direct Touch begin ignored because a touch is already active")
                return
            }
            guard state.supports(contacts) else { return }
            state.currentContacts = state.clamped(contacts)
            state.send(contacts: state.currentContacts, direction: .down, description: "live Direct Touch begin")
        }
    }

    public func update(contacts: [TouchContactPoint]) {
        enqueue { state in
            guard !state.currentContacts.isEmpty else {
                state.logger.warn("live Direct Touch update ignored because no touch is active")
                return
            }
            guard state.supports(contacts) else { return }
            let nextContacts = state.clamped(contacts)
            guard nextContacts != state.currentContacts else { return }
            state.currentContacts = nextContacts
            state.send(contacts: nextContacts, direction: .down, description: "live Direct Touch update")
        }
    }

    public func end(contacts: [TouchContactPoint]? = nil) {
        enqueue { state in
            guard !state.currentContacts.isEmpty else { return }
            let finalContacts = contacts.flatMap { state.supports($0) ? state.clamped($0) : nil }
                ?? state.currentContacts
            state.send(contacts: finalContacts, direction: .up, description: "live Direct Touch end")
            state.currentContacts = []
        }
    }

    public func cancel() {
        end()
    }

    private func enqueue(_ work: @escaping @Sendable (LiveDirectTouchSession) -> Void) {
        queue.async { work(self) }
    }

    private func supports(_ contacts: [TouchContactPoint]) -> Bool {
        guard contacts.count == 1 || contacts.count == 2 else {
            logger.warn("live Direct Touch unsupported contact count=\(contacts.count)")
            return false
        }
        return true
    }

    private func clamped(_ contacts: [TouchContactPoint]) -> [TouchContactPoint] {
        contacts.sorted { $0.identifier < $1.identifier }.map { contact in
            TouchContactPoint(
                identifier: contact.identifier,
                point: SimulatorPoint(
                    x: min(max(contact.point.x, 0), metrics.pointSize.width),
                    y: min(max(contact.point.y, 0), metrics.pointSize.height)
                )
            )
        }
    }

    private func send(contacts: [TouchContactPoint], direction: TouchDirection, description: String) {
        do {
            let message: UnsafeMutableRawPointer
            switch contacts.count {
            case 1:
                message = try TouchMessageBuilder.singleTouch(
                    point: contacts[0].point.cgPoint,
                    screenPointSize: metrics.pointSize,
                    direction: direction
                )
            case 2:
                message = try TouchMessageBuilder.twoFingerTouch(
                    finger1: contacts[0].point.cgPoint,
                    finger2: contacts[1].point.cgPoint,
                    screenPointSize: metrics.pointSize,
                    direction: direction
                )
            default:
                return
            }
            logTouchEventIfEnabled(description: description, direction: direction, contacts: contacts)
            if dumpsHIDMessages {
                logger.info("message \(TouchMessageBuilder.describe(message))")
            }
            hidClient.send(message: message, waitForCompletion: false) { [weak self] error in
                guard let error else { return }
                self?.logger.error("\(description) failed: \(error)")
                self?.onError?(error)
            }
        } catch {
            let message = String(describing: error)
            logger.error("\(description) failed: \(message)")
            onError?(message)
        }
    }

    private func logTouchEventIfEnabled(
        description: String,
        direction: TouchDirection,
        contacts: [TouchContactPoint]
    ) {
        guard logsTouchEvents else { return }
        let points = contacts.map { "\($0.identifier):(\($0.point.x), \($0.point.y))" }.joined(separator: " ")
        logger.info("\(description) direction=\(direction) contacts=\(points)")
    }
}
