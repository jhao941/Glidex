import GlidexCore
import Testing

@Suite("Status item presentation")
struct StatusItemPresentationTests {
    @Test("menu bar symbols use macOS template rendering")
    func templateRendering() {
        #expect(StatusItemPresentation(snapshot: GlidexAppSnapshot()).usesTemplateImage)
    }
    @Test("runtime states use distinguishable symbols")
    func distinctSymbols() {
        let statuses: [GlidexRuntimeStatus] = [
            .active,
            .waiting("test"),
            .connecting,
            .paused,
            .error(.ambiguousTarget),
        ]
        let symbols = statuses.map {
            StatusItemPresentation(snapshot: GlidexAppSnapshot(status: $0)).symbolName
        }

        #expect(Set(symbols).count == statuses.count)
    }

    @Test("Option feedback distinguishes ready outside and active")
    func optionFeedback() {
        let ready = StatusItemPresentation(snapshot: GlidexAppSnapshot(status: .active))
        let outside = StatusItemPresentation(snapshot: GlidexAppSnapshot(
            status: .active,
            optionAnchorAvailability: .outsideSimulator
        ))
        let active = StatusItemPresentation(snapshot: GlidexAppSnapshot(
            status: .active,
            optionAnchorAvailability: .available(SimulatorPoint(x: 20, y: 30))
        ))

        #expect(ready.optionAnchorText == "Available - hold Option")
        #expect(!ready.showsOptionAnchorStatus)
        #expect(outside.optionAnchorText == "Pointer outside Simulator")
        #expect(outside.showsOptionAnchorStatus)
        #expect(active.optionAnchorText == "Active at pointer")
        #expect(active.showsOptionAnchorStatus)
    }

    @Test("Direct Touch is presented as a stable input mode")
    func directTouchPresentation() {
        let presentation = StatusItemPresentation(snapshot: GlidexAppSnapshot(
            preferences: GlidexPreferenceValues(inputMode: .directTouch)
        ))

        #expect(presentation.modeText == "Direct Touch")
        #expect(!presentation.showsOptionAnchorStatus)
    }
}
