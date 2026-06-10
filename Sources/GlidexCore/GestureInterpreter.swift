import CoreGraphics
import Foundation

public struct InterpretedGesture: Equatable, Sendable {
    public let contactIDs: [Int32]
    public let intent: GestureIntent
    public let initialCentroid: NormalizedTouchPoint
    public let centroid: NormalizedTouchPoint
    public let initialDistance: CGFloat
    public let distance: CGFloat

    public init(
        contactIDs: [Int32],
        intent: GestureIntent,
        initialCentroid: NormalizedTouchPoint,
        centroid: NormalizedTouchPoint,
        initialDistance: CGFloat,
        distance: CGFloat
    ) {
        self.contactIDs = contactIDs
        self.intent = intent
        self.initialCentroid = initialCentroid
        self.centroid = centroid
        self.initialDistance = initialDistance
        self.distance = distance
    }
}

public enum GestureInterpreterOutput: Equatable, Sendable {
    case pending
    case began(InterpretedGesture)
    case changed(InterpretedGesture)
    case ended
}

public struct GestureInterpreter: Sendable {
    private struct State: Sendable {
        var contactIDs: (Int32, Int32)
        var initialTimestamp: Double
        var initialCentroid: NormalizedTouchPoint
        var initialDistance: CGFloat
        var intent: GestureIntent?
    }

    private var state: State?
    private var lastFrameNumber: Int32?

    public init() {}

    public mutating func consume(_ frame: RawTouchFrame) -> GestureInterpreterOutput? {
        guard frame.frame != lastFrameNumber else { return nil }
        lastFrameNumber = frame.frame

        let contacts = frame.contacts.sorted { $0.identifier < $1.identifier }
        if trackedContactEnded(in: contacts) {
            state = nil
            return .ended
        }

        let activeContacts = contacts.filter(\.isActive)
        guard activeContacts.count >= 2 else {
            guard state != nil else { return nil }
            state = nil
            return .ended
        }

        let first = activeContacts[0]
        let second = activeContacts[1]
        let contactIDs = (first.identifier, second.identifier)
        let centroid = Self.centroid(first.normalizedPosition, second.normalizedPosition)
        let distance = first.normalizedPosition.distance(to: second.normalizedPosition)

        if state?.contactIDs.0 != contactIDs.0 || state?.contactIDs.1 != contactIDs.1 {
            state = State(
                contactIDs: contactIDs,
                initialTimestamp: frame.timestamp,
                initialCentroid: centroid,
                initialDistance: distance,
                intent: nil
            )
        }

        guard var current = state else { return nil }
        let isBeginning = current.intent == nil
        if current.intent == nil {
            current.intent = Self.resolveIntent(
                state: current,
                centroid: centroid,
                distance: distance,
                timestamp: frame.timestamp
            )
            state = current
        }

        guard let intent = current.intent else { return .pending }
        let gesture = InterpretedGesture(
            contactIDs: [current.contactIDs.0, current.contactIDs.1],
            intent: intent,
            initialCentroid: current.initialCentroid,
            centroid: centroid,
            initialDistance: current.initialDistance,
            distance: distance
        )
        return isBeginning ? .began(gesture) : .changed(gesture)
    }

    public mutating func cancel() -> GestureInterpreterOutput? {
        guard state != nil else { return nil }
        state = nil
        return .ended
    }

    private func trackedContactEnded(in contacts: [RawTouchContact]) -> Bool {
        guard let state else { return false }
        return contacts.contains { contact in
            (contact.identifier == state.contactIDs.0 || contact.identifier == state.contactIDs.1)
                && !contact.isActive
        }
    }

    private static func resolveIntent(
        state: State,
        centroid: NormalizedTouchPoint,
        distance: CGFloat,
        timestamp: Double
    ) -> GestureIntent? {
        let elapsed = timestamp - state.initialTimestamp
        let centroidDelta = state.initialCentroid.distance(to: centroid)
        let distanceDelta = abs(distance - state.initialDistance)

        if distanceDelta >= 0.010 && distanceDelta > centroidDelta * 1.15 {
            return .pinch
        }
        if distanceDelta >= 0.018 {
            return .pinch
        }
        if centroidDelta >= 0.010 && distanceDelta < centroidDelta * 1.2 {
            return .navigate
        }
        if elapsed >= 0.070 && centroidDelta >= 0.006 {
            return .navigate
        }
        return nil
    }

    private static func centroid(_ first: NormalizedTouchPoint, _ second: NormalizedTouchPoint) -> NormalizedTouchPoint {
        NormalizedTouchPoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
        )
    }
}

private extension NormalizedTouchPoint {
    func distance(to other: NormalizedTouchPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
