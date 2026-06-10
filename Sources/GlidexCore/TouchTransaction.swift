import Foundation

public struct TouchTransactionSnapshot: Equatable, Sendable {
    public let gestureID: UUID
    public let source: TouchSource
    public let intent: GestureIntent
    public let anchor: SimulatorPoint
    public let contacts: [TouchContactPoint]

    public init(
        gestureID: UUID,
        source: TouchSource,
        intent: GestureIntent,
        anchor: SimulatorPoint,
        contacts: [TouchContactPoint]
    ) {
        self.gestureID = gestureID
        self.source = source
        self.intent = intent
        self.anchor = anchor
        self.contacts = contacts
    }
}

public enum TouchLifecycleEvent: Equatable, Sendable {
    case begin(TouchTransactionSnapshot)
    case update(TouchTransactionSnapshot)
    case end(TouchTransactionSnapshot)
    case cancel(TouchTransactionSnapshot)
}

public protocol TouchSink: AnyObject {
    func receive(_ event: TouchLifecycleEvent)
}

public final class TouchTransaction {
    public enum State: Equatable, Sendable {
        case idle
        case active
        case ended
        case cancelled
    }

    public let gestureID: UUID
    public let source: TouchSource
    public let intent: GestureIntent
    public let anchor: SimulatorPoint

    public private(set) var state: State = .idle
    public private(set) var contacts: [TouchContactPoint] = []

    private weak var sink: TouchSink?

    public init(
        gestureID: UUID = UUID(),
        source: TouchSource,
        intent: GestureIntent,
        anchor: SimulatorPoint,
        sink: TouchSink
    ) {
        self.gestureID = gestureID
        self.source = source
        self.intent = intent
        self.anchor = anchor
        self.sink = sink
    }

    @discardableResult
    public func begin(contacts: [TouchContactPoint]) -> Bool {
        guard state == .idle, !contacts.isEmpty else { return false }
        self.contacts = contacts
        state = .active
        sink?.receive(.begin(snapshot))
        return true
    }

    @discardableResult
    public func update(contacts: [TouchContactPoint]) -> Bool {
        guard state == .active, !contacts.isEmpty else { return false }
        guard contacts != self.contacts else { return false }
        self.contacts = contacts
        sink?.receive(.update(snapshot))
        return true
    }

    @discardableResult
    public func end(contacts: [TouchContactPoint]? = nil) -> Bool {
        guard state == .active else { return false }
        if let contacts, !contacts.isEmpty {
            self.contacts = contacts
        }
        state = .ended
        sink?.receive(.end(snapshot))
        return true
    }

    @discardableResult
    public func cancel() -> Bool {
        guard state == .active else { return false }
        state = .cancelled
        sink?.receive(.cancel(snapshot))
        return true
    }

    private var snapshot: TouchTransactionSnapshot {
        TouchTransactionSnapshot(
            gestureID: gestureID,
            source: source,
            intent: intent,
            anchor: anchor,
            contacts: contacts
        )
    }
}
