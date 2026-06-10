import GlidexCore
import Testing

@Suite("Overlay presentation")
struct OverlayPresentationTests {
    @Test("border visibility never changes whole-window opacity")
    func windowOpacityIsConstant() {
        for visibility in BorderVisibility.allCases {
            let snapshot = GlidexAppSnapshot(preferences: GlidexPreferenceValues(
                borderVisibility: visibility
            ))
            let presentation = OverlayPresentation(snapshot: snapshot)

            #expect(OverlayPresentation.windowAlpha == 1)
            #expect(presentation.borderAlpha == visibility.alpha)
        }
    }

    @Test("paused and error states pass input through")
    func inactiveStatesPassThrough() {
        let paused = OverlayPresentation(snapshot: GlidexAppSnapshot(
            preferences: GlidexPreferenceValues(isEnabled: false)
        ))
        let failed = OverlayPresentation(snapshot: GlidexAppSnapshot(
            status: .error(.accessibilityPermission)
        ))

        #expect(!paused.acceptsInput)
        #expect(!failed.acceptsInput)
    }

    @Test("calibration accepts input while waiting")
    func calibrationAcceptsInput() {
        let presentation = OverlayPresentation(snapshot: GlidexAppSnapshot(
            status: .waiting("Simulator moving"),
            isCalibrationMode: true
        ))

        #expect(presentation.acceptsInput)
    }

    @Test("leaving active input requires transaction cancellation")
    func deactivationRequiresCancellation() {
        let paused = OverlayPresentation(snapshot: GlidexAppSnapshot(
            preferences: GlidexPreferenceValues(isEnabled: false)
        ))
        let failed = OverlayPresentation(snapshot: GlidexAppSnapshot(
            status: .error(.multitouchUnavailable("test"))
        ))

        #expect(OverlayPresentation.requiresCancellation(
            previouslyAcceptedInput: true,
            presentation: paused
        ))
        #expect(OverlayPresentation.requiresCancellation(
            previouslyAcceptedInput: true,
            presentation: failed
        ))
        #expect(!OverlayPresentation.requiresCancellation(
            previouslyAcceptedInput: false,
            presentation: failed
        ))
    }
}
