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
        #expect(outside.optionAnchorText == "Pointer outside Simulator")
        #expect(active.optionAnchorText == "Active at pointer")
    }
}
