import CoreGraphics
import Foundation

public struct CoordinateMapper: Equatable, Sendable {
    public var captureRect: CGRect
    public var simulatorSize: SimulatorPointSize

    public init(captureRect: CGRect, simulatorSize: SimulatorPointSize) {
        self.captureRect = captureRect
        self.simulatorSize = simulatorSize
    }

    public func simulatorPoint(fromCapture point: CapturePoint) -> SimulatorPoint? {
        guard captureRect.contains(point.cgPoint), captureRect.width > 0, captureRect.height > 0 else {
            return nil
        }

        return projectedSimulatorPoint(fromCapture: point)
    }

    public func projectedSimulatorPoint(fromCapture point: CapturePoint) -> SimulatorPoint? {
        guard captureRect.width > 0, captureRect.height > 0 else { return nil }

        let normalizedX = (point.x - captureRect.minX) / captureRect.width
        let normalizedYFromTop = (captureRect.maxY - point.y) / captureRect.height
        return SimulatorPoint(
            x: normalizedX * simulatorSize.width,
            y: normalizedYFromTop * simulatorSize.height
        )
    }

    public func simulatorPoint(fromNormalizedTouch point: NormalizedTouchPoint) -> SimulatorPoint {
        let x = min(max(point.x, 0), 1)
        let y = min(max(point.y, 0), 1)
        return clamped(SimulatorPoint(
            x: x * simulatorSize.width,
            y: (1 - y) * simulatorSize.height
        ))
    }

    public func capturePoint(fromSimulator point: SimulatorPoint) -> CapturePoint? {
        guard simulatorSize.width > 0, simulatorSize.height > 0 else { return nil }
        return CapturePoint(
            x: captureRect.minX + point.x / simulatorSize.width * captureRect.width,
            y: captureRect.maxY - point.y / simulatorSize.height * captureRect.height
        )
    }

    public func clamped(_ point: SimulatorPoint) -> SimulatorPoint {
        SimulatorPoint(
            x: min(max(point.x, 0), simulatorSize.width),
            y: min(max(point.y, 0), simulatorSize.height)
        )
    }
}
