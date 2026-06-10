import Foundation

public enum TouchLogPhase: String, Equatable, Sendable {
    case begin
    case update
    case end
    case cancel
}

public struct TouchLogRecord: Equatable, Sendable {
    public let gestureID: UUID
    public let source: TouchSource
    public let intent: GestureIntent
    public let anchor: SimulatorPoint
    public let phase: TouchLogPhase
    public let contacts: [TouchContactPoint]

    public init(event: TouchLifecycleEvent) {
        switch event {
        case let .begin(snapshot):
            self.init(snapshot: snapshot, phase: .begin)
        case let .update(snapshot):
            self.init(snapshot: snapshot, phase: .update)
        case let .end(snapshot):
            self.init(snapshot: snapshot, phase: .end)
        case let .cancel(snapshot):
            self.init(snapshot: snapshot, phase: .cancel)
        }
    }

    public var message: String {
        let contactList = contacts
            .map { "\($0.identifier):\(format($0.point.x)),\(format($0.point.y))" }
            .joined(separator: ";")
        return "event=touch gestureID=\(gestureID.uuidString) source=\(source.rawValue) " +
            "intent=\(intent.rawValue) anchor=\(format(anchor.x)),\(format(anchor.y)) " +
            "phase=\(phase.rawValue) contacts=\(contactList)"
    }

    private init(snapshot: TouchTransactionSnapshot, phase: TouchLogPhase) {
        self.gestureID = snapshot.gestureID
        self.source = snapshot.source
        self.intent = snapshot.intent
        self.anchor = snapshot.anchor
        self.phase = phase
        self.contacts = snapshot.contacts
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

public extension Logger {
    func touch(_ event: TouchLifecycleEvent) {
        info(TouchLogRecord(event: event).message)
    }
}
