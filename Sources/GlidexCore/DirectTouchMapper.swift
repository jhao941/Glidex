import Foundation

public enum DirectTouchMapperOutput: Equatable, Sendable {
    case began([TouchContactPoint])
    case changed([TouchContactPoint])
    case ended([TouchContactPoint])
    case cancelled([TouchContactPoint])
}

public struct DirectTouchMapper: Sendable {
    private let coordinateMapper: CoordinateMapper
    private var activeContacts: [TouchContactPoint] = []
    private var lastFrameNumber: Int32?

    public init(coordinateMapper: CoordinateMapper) {
        self.coordinateMapper = coordinateMapper
    }

    public mutating func consume(_ frame: RawTouchFrame) -> DirectTouchMapperOutput? {
        guard frame.frame != lastFrameNumber else { return nil }
        lastFrameNumber = frame.frame

        let nextContacts = mappedContacts(frame.contacts.filter(\.isActive))
        if activeContacts.isEmpty {
            guard !nextContacts.isEmpty else { return nil }
            activeContacts = nextContacts
            return .began(nextContacts)
        }

        guard !nextContacts.isEmpty else {
            let finalContacts = terminalContacts(from: frame.contacts)
            activeContacts = []
            return .ended(finalContacts)
        }

        guard nextContacts != activeContacts else { return nil }
        activeContacts = nextContacts
        return .changed(nextContacts)
    }

    public mutating func cancel() -> DirectTouchMapperOutput? {
        guard !activeContacts.isEmpty else { return nil }
        let contacts = activeContacts
        activeContacts = []
        return .cancelled(contacts)
    }

    private func mappedContacts(_ contacts: [RawTouchContact]) -> [TouchContactPoint] {
        var contactsByIdentifier: [Int32: RawTouchContact] = [:]
        for contact in contacts {
            contactsByIdentifier[contact.identifier] = contact
        }
        return contactsByIdentifier.values
            .sorted { $0.identifier < $1.identifier }
            .map { contact in
                TouchContactPoint(
                    identifier: Int(contact.identifier),
                    point: coordinateMapper.simulatorPoint(fromNormalizedTouch: contact.normalizedPosition)
                )
            }
    }

    private func terminalContacts(from contacts: [RawTouchContact]) -> [TouchContactPoint] {
        let previousIdentifiers = Set(activeContacts.map(\.identifier))
        let terminal = mappedContacts(contacts.filter { previousIdentifiers.contains(Int($0.identifier)) })
        return terminal.isEmpty ? activeContacts : terminal
    }
}
