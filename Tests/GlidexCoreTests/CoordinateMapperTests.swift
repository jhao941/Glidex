import CoreGraphics
import Testing
@testable import GlidexCore

@Suite("CoordinateMapper")
struct CoordinateMapperTests {
    private let mapper = CoordinateMapper(
        captureRect: CGRect(x: 10, y: 20, width: 200, height: 400),
        simulatorSize: SimulatorPointSize(width: 400, height: 800)
    )

    @Test("capture coordinates preserve AppKit-to-simulator Y inversion")
    func captureCoordinates() {
        #expect(mapper.simulatorPoint(fromCapture: CapturePoint(x: 10, y: 20)) == SimulatorPoint(x: 0, y: 800))
        #expect(mapper.simulatorPoint(fromCapture: CapturePoint(x: 110, y: 320)) == SimulatorPoint(x: 200, y: 200))
        #expect(mapper.simulatorPoint(fromCapture: CapturePoint(x: 110, y: 220)) == SimulatorPoint(x: 200, y: 400))
    }

    @Test("points outside capture bounds are rejected")
    func outsideCaptureBounds() {
        #expect(mapper.simulatorPoint(fromCapture: CapturePoint(x: 9, y: 220)) == nil)
        #expect(mapper.simulatorPoint(fromCapture: CapturePoint(x: 210, y: 420)) == nil)
    }

    @Test("raw normalized coordinates are clamped")
    func normalizedCoordinates() {
        #expect(mapper.simulatorPoint(fromNormalizedTouch: NormalizedTouchPoint(x: -1, y: 2)) == SimulatorPoint(x: 0, y: 0))
        #expect(mapper.simulatorPoint(fromNormalizedTouch: NormalizedTouchPoint(x: 0.5, y: 0.25)) == SimulatorPoint(x: 200, y: 600))
    }
}
