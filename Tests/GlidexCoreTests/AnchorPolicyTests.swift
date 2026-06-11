import Testing
@testable import GlidexCore

@Suite("AnchorPolicy")
struct AnchorPolicyTests {
    private let fallback = SimulatorPoint(x: 100, y: 200)
    private let size = SimulatorPointSize(width: 400, height: 800)

    @Test("point policy prefers the explicit cursor point")
    func pointPolicy() {
        #expect(AnchorPolicy.point(SimulatorPoint(x: 20, y: 30)).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 20, y: 30))
        #expect(AnchorPolicy.point(nil).resolve(fallback: fallback, simulatorSize: size) == fallback)
    }

    @Test("edge policy preserves the unconstrained axis")
    func edgePolicy() {
        #expect(AnchorPolicy.edge(.leading).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 1, y: 200))
        #expect(AnchorPolicy.edge(.bottom).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 100, y: 799))
    }

    @Test("all four edges preserve the fixed anchor axis and clamp it")
    func fixedEdgePosition() {
        let fixed = SimulatorPoint(x: 275, y: 625)
        #expect(AnchorPolicy.edge(.leading, fixedPoint: fixed).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 1, y: 625))
        #expect(AnchorPolicy.edge(.trailing, fixedPoint: fixed).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 399, y: 625))
        #expect(AnchorPolicy.edge(.top, fixedPoint: fixed).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 275, y: 1))
        #expect(AnchorPolicy.edge(.bottom, fixedPoint: fixed).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 275, y: 799))
        #expect(AnchorPolicy.edge(.leading, fixedPoint: SimulatorPoint(x: -20, y: 900)).resolve(fallback: fallback, simulatorSize: size) == SimulatorPoint(x: 1, y: 800))
    }

    @Test("nearest edge selection is explicit and deterministic")
    func nearestEdge() {
        #expect(AnchorPolicy.nearestEdge(to: SimulatorPoint(x: 2, y: 300), simulatorSize: size) == .leading)
        #expect(AnchorPolicy.nearestEdge(to: SimulatorPoint(x: 200, y: 799), simulatorSize: size) == .bottom)
    }
}
