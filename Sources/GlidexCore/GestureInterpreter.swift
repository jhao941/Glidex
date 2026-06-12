import CoreGraphics
import Foundation

public struct InterpretedGesture: Equatable, Sendable {
    public let contactIDs: [Int32]
    public let intent: GestureIntent
    public let initialCentroid: NormalizedTouchPoint
    public let centroid: NormalizedTouchPoint
    public let initialDistance: CGFloat
    public let distance: CGFloat
    public let rotationDelta: CGFloat

    public init(
        contactIDs: [Int32],
        intent: GestureIntent,
        initialCentroid: NormalizedTouchPoint,
        centroid: NormalizedTouchPoint,
        initialDistance: CGFloat,
        distance: CGFloat,
        rotationDelta: CGFloat
    ) {
        self.contactIDs = contactIDs
        self.intent = intent
        self.initialCentroid = initialCentroid
        self.centroid = centroid
        self.initialDistance = initialDistance
        self.distance = distance
        self.rotationDelta = rotationDelta
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
        var initialFirstPosition: NormalizedTouchPoint
        var initialSecondPosition: NormalizedTouchPoint
        var initialCentroid: NormalizedTouchPoint
        var initialDistance: CGFloat
        var intent: GestureIntent?
    }

    private var state: State?
    private var lastFrameNumber: Int32?
    private let tuning: InputTuning

    public init(tuning: InputTuning = .stable) {
        self.tuning = tuning
    }

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
                initialFirstPosition: first.normalizedPosition,
                initialSecondPosition: second.normalizedPosition,
                initialCentroid: centroid,
                initialDistance: distance,
                intent: nil
            )
        }

        guard var current = state else { return nil }
        let isBeginning = current.intent == nil
        if current.intent == nil {
            current.intent = resolveIntent(
                state: current,
                firstPosition: first.normalizedPosition,
                secondPosition: second.normalizedPosition,
                centroid: centroid,
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
            distance: distance,
            rotationDelta: Self.normalizedAngle(
                Self.angle(from: first.normalizedPosition, to: second.normalizedPosition) -
                    Self.angle(from: current.initialFirstPosition, to: current.initialSecondPosition)
            )
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

    private func resolveIntent(
        state: State,
        firstPosition: NormalizedTouchPoint,
        secondPosition: NormalizedTouchPoint,
        centroid: NormalizedTouchPoint,
        timestamp: Double
    ) -> GestureIntent? {
        let elapsed = timestamp - state.initialTimestamp
        let centroidDelta = state.initialCentroid.distance(to: centroid)
        let firstMovement = firstPosition - state.initialFirstPosition
        let secondMovement = secondPosition - state.initialSecondPosition
        let relativeMovement = secondMovement - firstMovement
        let initialAxis = (state.initialSecondPosition - state.initialFirstPosition).normalized
        let firstAxialMovement = firstMovement.dot(initialAxis)
        let secondAxialMovement = secondMovement.dot(initialAxis)
        let axialSeparation = abs(relativeMovement.dot(initialAxis))
        let fingersMoveOppositelyAlongAxis = firstAxialMovement * secondAxialMovement < 0
            && min(abs(firstAxialMovement), abs(secondAxialMovement)) >= tuning.pinchMinimumFingerMovement
        let bothFingersMoved = min(firstMovement.magnitude, secondMovement.magnitude) >=
            tuning.pinchMinimumFingerMovement

        if axialSeparation >= tuning.pinchIntentThreshold,
           axialSeparation > centroidDelta * tuning.pinchDominanceRatio,
           fingersMoveOppositelyAlongAxis {
            return .pinch
        }
        if centroidDelta >= tuning.navigationIntentThreshold,
           !fingersMoveOppositelyAlongAxis,
           bothFingersMoved {
            return .navigate
        }
        if elapsed >= tuning.navigationFallbackDelay && centroidDelta >= tuning.navigationFallbackThreshold {
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

    private static func angle(from first: NormalizedTouchPoint, to second: NormalizedTouchPoint) -> CGFloat {
        atan2(second.y - first.y, second.x - first.x)
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        atan2(sin(angle), cos(angle))
    }
}

private extension NormalizedTouchPoint {
    func distance(to other: NormalizedTouchPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    static func - (lhs: NormalizedTouchPoint, rhs: NormalizedTouchPoint) -> NormalizedTouchVector {
        NormalizedTouchVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

private extension NormalizedTouchVector {
    static func - (lhs: NormalizedTouchVector, rhs: NormalizedTouchVector) -> NormalizedTouchVector {
        NormalizedTouchVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    var magnitude: CGFloat {
        hypot(x, y)
    }

    var normalized: NormalizedTouchVector {
        let length = magnitude
        guard length > 0 else { return .zero }
        return NormalizedTouchVector(x: x / length, y: y / length)
    }

    func dot(_ other: NormalizedTouchVector) -> CGFloat {
        x * other.x + y * other.y
    }
}
