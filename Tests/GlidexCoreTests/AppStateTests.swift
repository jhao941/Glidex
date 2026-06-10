import Testing
@testable import GlidexCore

@Suite("Glidex app state")
@MainActor
struct AppStateTests {
    @Test("startup is enabled and waits in Navigate")
    func startupPolicy() {
        let state = GlidexAppState()
        #expect(state.snapshot.preferences.isEnabled)
        #expect(state.snapshot.preferences.inputMode == .navigate)
        #expect(state.snapshot.status == .waiting("Looking for Simulator"))
    }

    @Test("disabling pauses and enabling returns to waiting")
    func enabledTransitions() {
        let state = GlidexAppState()
        state.transition(to: .active)
        state.setEnabled(false)
        #expect(state.snapshot.status == .paused)
        #expect(!state.snapshot.acceptsInput)
        state.setEnabled(true)
        #expect(state.snapshot.status == .waiting("Looking for Simulator"))
    }

    @Test("Disabled input mode is normalized to Navigate")
    func disabledCompatibility() {
        let state = GlidexAppState()
        state.setInputMode(.disabled)
        #expect(state.snapshot.preferences.inputMode == .navigate)
    }

    @Test("errors retain a specific recovery reason")
    func errorState() {
        let state = GlidexAppState()
        state.transition(to: .error(.ambiguousTarget))
        #expect(state.snapshot.status == .error(.ambiguousTarget))
    }

    @Test("identical state changes are not rebroadcast")
    func identicalStateIsQuiet() {
        let state = GlidexAppState()
        var observations = 0
        _ = state.observe { _ in observations += 1 }

        state.transition(to: .waiting("Looking for Simulator"))
        state.setInputMode(.navigate)

        #expect(observations == 1)
    }
}
