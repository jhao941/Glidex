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
        #expect(state.snapshot.preferences.requiresPointerOverSimulator)
        #expect(state.snapshot.status == .waiting("Looking for Simulator"))
    }

    @Test("pointer requirement can be disabled")
    func pointerRequirement() {
        let state = GlidexAppState()
        state.setRequiresPointerOverSimulator(false)
        #expect(!state.snapshot.preferences.requiresPointerOverSimulator)
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

    @Test("Direct Touch does not expose anchor locking")
    func directTouchAnchorPolicy() {
        let state = GlidexAppState()
        state.setInputMode(.directTouch)
        #expect(state.snapshot.preferences.inputMode == .directTouch)
        #expect(state.snapshot.anchorLockState == .unavailable)
        state.setAnchorLocked(true)
        #expect(!state.snapshot.preferences.prefersAnchorLocked)
    }

    @Test("Direct Touch admits raw input from the first contact")
    func directTouchAdmissionThreshold() {
        #expect(CaptureInputMode.directTouch.rawInputStartContactCount == 1)
        #expect(CaptureInputMode.navigate.rawInputStartContactCount == 2)
        #expect(CaptureInputMode.point.rawInputStartContactCount == 2)
        #expect(CaptureInputMode.edge.rawInputStartContactCount == 2)
    }

    @Test("Direct Touch shortcut restores the previous input mode")
    func directTouchShortcutRestoresPreviousMode() {
        let state = GlidexAppState()
        state.setInputMode(.edge)

        state.toggleDirectTouchMode()
        #expect(state.snapshot.preferences.inputMode == .directTouch)

        state.toggleDirectTouchMode()
        #expect(state.snapshot.preferences.inputMode == .edge)
    }

    @Test("Direct Touch restored at launch falls back to Navigate")
    func restoredDirectTouchShortcutFallsBackToNavigate() {
        let state = GlidexAppState(snapshot: GlidexAppSnapshot(
            preferences: GlidexPreferenceValues(inputMode: .directTouch)
        ))

        state.toggleDirectTouchMode()
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
