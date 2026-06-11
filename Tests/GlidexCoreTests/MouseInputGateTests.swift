import Testing
@testable import GlidexCore

@Suite("Mouse input gate")
struct MouseInputGateTests {
    @Test("ordinary mouse click remains enabled")
    func ordinaryClick() {
        var gate = MouseInputGate()

        let down = gate.shouldHandle(.down, isTouchDerived: false)
        let up = gate.shouldHandle(.up, isTouchDerived: false)

        #expect(down)
        #expect(up)
    }

    @Test("touch-derived mouse sequence is suppressed")
    func touchDerivedClick() {
        var gate = MouseInputGate()

        let down = gate.shouldHandle(.down, isTouchDerived: true)
        let dragged = gate.shouldHandle(.dragged, isTouchDerived: false)
        let up = gate.shouldHandle(.up, isTouchDerived: false)

        #expect(!down)
        #expect(!dragged)
        #expect(!up)
    }

    @Test("suppression ends with the derived sequence")
    func nextMouseClick() {
        var gate = MouseInputGate()

        let derivedDown = gate.shouldHandle(.down, isTouchDerived: true)
        let derivedUp = gate.shouldHandle(.up, isTouchDerived: true)
        let mouseDown = gate.shouldHandle(.down, isTouchDerived: false)
        let mouseUp = gate.shouldHandle(.up, isTouchDerived: false)

        #expect(!derivedDown)
        #expect(!derivedUp)
        #expect(mouseDown)
        #expect(mouseUp)
    }
}
