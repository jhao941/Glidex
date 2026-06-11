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
    case edge(SimulatorEdge, fixedPoint: SimulatorPoint?)

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
        case let .edge(edge, fixedPoint):
            let point = fixedPoint ?? fallback
            switch edge {
            case .leading:
                return clamped(SimulatorPoint(x: edgeInset, y: point.y), simulatorSize: simulatorSize)
            case .trailing:
                return clamped(SimulatorPoint(x: simulatorSize.width - edgeInset, y: point.y), simulatorSize: simulatorSize)
            case .top:
                return clamped(SimulatorPoint(x: point.x, y: edgeInset), simulatorSize: simulatorSize)
            case .bottom:
                return clamped(SimulatorPoint(x: point.x, y: simulatorSize.height - edgeInset), simulatorSize: simulatorSize)
            }
        }
    }

    private func clamped(_ point: SimulatorPoint, simulatorSize: SimulatorPointSize) -> SimulatorPoint {
        SimulatorPoint(
            x: min(max(point.x, 0), simulatorSize.width),
            y: min(max(point.y, 0), simulatorSize.height)
        )
    }
}

public extension AnchorPolicy {
    static func edge(_ edge: SimulatorEdge) -> AnchorPolicy {
        .edge(edge, fixedPoint: nil)
    }
}

public extension AnchorPolicy {
    static func nearestEdge(to point: SimulatorPoint, simulatorSize: SimulatorPointSize) -> SimulatorEdge {
        let distances: [(SimulatorEdge, CGFloat)] = [
            (.leading, point.x),
            (.trailing, simulatorSize.width - point.x),
            (.top, point.y),
            (.bottom, simulatorSize.height - point.y),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .leading
    }
}
