public enum AnchorPointerPhase: Equatable, Sendable {
    case hover
    case down
    case drag
    case up
}

public enum AnchorEditingPolicy {
    public static func accepts(
        _ phase: AnchorPointerPhase,
        mode: CaptureInputMode,
        isLocked: Bool
    ) -> Bool {
        guard !isLocked, mode == .point || mode == .edge else { return false }
        return phase == .down || phase == .drag
    }
}
