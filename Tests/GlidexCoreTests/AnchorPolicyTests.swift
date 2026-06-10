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
}
