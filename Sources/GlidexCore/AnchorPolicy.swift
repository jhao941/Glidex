import Foundation

public enum SimulatorEdge: Equatable, Sendable {
    case leading
    case trailing
    case top
    case bottom
}

public enum AnchorPolicy: Equatable, Sendable {
    case navigate
    case point(SimulatorPoint?)
    case edge(SimulatorEdge)

    public func resolve(
        fallback: SimulatorPoint,
        simulatorSize: SimulatorPointSize,
        edgeInset: CGFloat = 1
    ) -> SimulatorPoint {
        switch self {
        case .navigate:
            return fallback
        case let .point(point):
            return point ?? fallback
        case let .edge(edge):
            switch edge {
            case .leading:
                return SimulatorPoint(x: edgeInset, y: fallback.y)
            case .trailing:
                return SimulatorPoint(x: max(0, simulatorSize.width - edgeInset), y: fallback.y)
            case .top:
                return SimulatorPoint(x: fallback.x, y: edgeInset)
            case .bottom:
                return SimulatorPoint(x: fallback.x, y: max(0, simulatorSize.height - edgeInset))
            }
        }
    }
}
