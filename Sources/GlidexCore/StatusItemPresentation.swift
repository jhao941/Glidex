import Foundation

public struct StatusItemPresentation: Equatable, Sendable {
    public var symbolName: String
    public var optionAnchorText: String
    public var usesTemplateImage: Bool { true }

    public init(snapshot: GlidexAppSnapshot) {
        self.symbolName = Self.symbolName(for: snapshot.status)
        self.optionAnchorText = Self.optionAnchorText(for: snapshot)
    }

    private static func symbolName(for status: GlidexRuntimeStatus) -> String {
        switch status {
        case .active: "hand.draw.fill"
        case .waiting: "hourglass"
        case .connecting: "arrow.triangle.2.circlepath"
        case .paused: "pause.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private static func optionAnchorText(for snapshot: GlidexAppSnapshot) -> String {
        guard snapshot.preferences.inputMode == .navigate else { return "Navigate mode only" }
        guard snapshot.status == .active, snapshot.preferences.isEnabled else { return "Unavailable" }
        switch snapshot.optionAnchorAvailability {
        case .inactive: return "Available - hold Option"
        case .outsideSimulator: return "Pointer outside Simulator"
        case .available: return "Active at pointer"
        }
    }
}
