import Foundation

enum DirectTouchFramePlanner {
    static func begin(_ contacts: [TouchContactPoint]) -> [DirectTouchContact] {
        contacts.map { messageContact($0, phase: .down) }
    }

    static func update(
        from previousContacts: [TouchContactPoint],
        to nextContacts: [TouchContactPoint]
    ) -> [[DirectTouchContact]] {
        let previous = Dictionary(uniqueKeysWithValues: previousContacts.map { ($0.identifier, $0) })
        let next = Dictionary(uniqueKeysWithValues: nextContacts.map { ($0.identifier, $0) })
        let retained = Set(previous.keys).intersection(next.keys)
        let removed = Set(previous.keys).subtracting(next.keys)
        let added = Set(next.keys).subtracting(previous.keys)
        let allIdentifiers = retained.union(removed).union(added)

        if allIdentifiers.count <= 5 {
            return [allIdentifiers.sorted().compactMap { identifier in
                if let contact = next[identifier] {
                    return messageContact(contact, phase: added.contains(identifier) ? .down : .move)
                }
                return previous[identifier].map { messageContact($0, phase: .up) }
            }]
        }

        let releaseFrame = previous.keys.sorted().compactMap { identifier -> DirectTouchContact? in
            if let contact = next[identifier] {
                return messageContact(contact, phase: .move)
            }
            return previous[identifier].map { messageContact($0, phase: .up) }
        }
        let additionFrame = next.keys.sorted().compactMap { identifier -> DirectTouchContact? in
            next[identifier].map { messageContact($0, phase: added.contains(identifier) ? .down : .move) }
        }
        return [releaseFrame, additionFrame]
    }

    static func end(
        currentContacts: [TouchContactPoint],
        finalContacts: [TouchContactPoint]
    ) -> [DirectTouchContact] {
        let finalPoints = Dictionary(uniqueKeysWithValues: finalContacts.map { ($0.identifier, $0.point) })
        return currentContacts.map { contact in
            messageContact(
                TouchContactPoint(identifier: contact.identifier, point: finalPoints[contact.identifier] ?? contact.point),
                phase: .up
            )
        }
    }

    private static func messageContact(
        _ contact: TouchContactPoint,
        phase: DirectTouchContactPhase
    ) -> DirectTouchContact {
        DirectTouchContact(
            identifier: UInt32(truncatingIfNeeded: contact.identifier),
            point: contact.point.cgPoint,
            phase: phase
        )
    }
}
