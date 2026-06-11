public enum MouseInputPhase: Sendable {
    case down
    case dragged
    case up
}

public struct MouseInputGate: Sendable {
    private var isSuppressingSequence = false

    public init() {}

    public mutating func shouldHandle(_ phase: MouseInputPhase, isTouchDerived: Bool) -> Bool {
        switch phase {
        case .down:
            isSuppressingSequence = isTouchDerived
            return !isSuppressingSequence
        case .dragged:
            return !isSuppressingSequence && !isTouchDerived
        case .up:
            defer { isSuppressingSequence = false }
            return !isSuppressingSequence && !isTouchDerived
        }
    }
}
