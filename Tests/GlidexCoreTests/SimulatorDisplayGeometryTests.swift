import CoreGraphics
import GlidexCore
import Testing

@Suite("Simulator display geometry")
struct SimulatorDisplayGeometryTests {
    @Test("Quartz frames convert across displays without assuming the first NSScreen")
    func multiDisplayConversion() {
        let space = DesktopCoordinateSpace(mainDisplayHeight: 1_080)

        #expect(space.appKitFrame(fromQuartzTopLeft: CGRect(
            x: 1_920,
            y: 100,
            width: 800,
            height: 600
        )) == CGRect(x: 1_920, y: 380, width: 800, height: 600))
        #expect(space.appKitFrame(fromQuartzTopLeft: CGRect(
            x: -1_280,
            y: -300,
            width: 1_280,
            height: 720
        )) == CGRect(x: -1_280, y: 660, width: 1_280, height: 720))
    }

    @Test("rotation swaps simulator points and preserves corner mapping")
    func landscapeGeometry() {
        let geometry = SimulatorDisplayGeometry(
            desktopFrame: CGRect(x: 2_000, y: 200, width: 874, height: 402),
            nativeSimulatorSize: SimulatorPointSize(width: 402, height: 874)
        )

        #expect(geometry.simulatorSize == SimulatorPointSize(width: 874, height: 402))
        #expect(geometry.mapper.projectedSimulatorPoint(fromCapture: CapturePoint(x: 874, y: 0)) == SimulatorPoint(x: 874, y: 402))
    }

    @Test("scale changes retain logical simulator points")
    func scaledGeometry() {
        let small = SimulatorDisplayGeometry(
            desktopFrame: CGRect(x: 0, y: 0, width: 201, height: 437),
            nativeSimulatorSize: SimulatorPointSize(width: 402, height: 874)
        )
        let large = SimulatorDisplayGeometry(
            desktopFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            nativeSimulatorSize: SimulatorPointSize(width: 402, height: 874)
        )

        #expect(small.mapper.simulatorPoint(fromCapture: CapturePoint(x: 100.5, y: 218.5)) == SimulatorPoint(x: 201, y: 437))
        #expect(large.mapper.simulatorPoint(fromCapture: CapturePoint(x: 201, y: 437)) == SimulatorPoint(x: 201, y: 437))
    }

    @Test("calibration adjustment follows a moved target")
    func calibrationAdjustment() {
        let adjustment = OverlayFrameAdjustment(
            base: CGRect(x: 100, y: 100, width: 400, height: 800),
            adjusted: CGRect(x: 104, y: 98, width: 394, height: 806)
        )

        #expect(adjustment.applying(to: CGRect(
            x: 2_000,
            y: 300,
            width: 500,
            height: 900
        )) == CGRect(x: 2_004, y: 298, width: 494, height: 906))
    }
}
