import Testing
@testable import GlidexCore

@Suite("Simulator target selection")
struct SimulatorTargetSelectorTests {
    @Test("one booted simulator may be selected without a title")
    func soleDevice() {
        let device = record(name: "iPhone 16 Pro", udid: "A")
        #expect(SimulatorTargetSelector.select(from: [device], windowTitle: nil)?.udid == "A")
    }

    @Test("window title selects the matching simulator")
    func titleMatch() {
        let phone = record(name: "iPhone 16 Pro", udid: "A")
        let tablet = record(name: "iPad Pro", udid: "B")
        #expect(SimulatorTargetSelector.select(from: [tablet, phone], windowTitle: "iPhone 16 Pro - iOS 26.0")?.udid == "A")
    }

    @Test("multiple devices without a title match are rejected")
    func ambiguousSelection() {
        let devices = [record(name: "iPhone 16 Pro", udid: "A"), record(name: "iPad Pro", udid: "B")]
        #expect(SimulatorTargetSelector.select(from: devices, windowTitle: nil) == nil)
        #expect(SimulatorTargetSelector.select(from: devices, windowTitle: "Simulator") == nil)
    }

    @Test("automatic attachment waits when Simulator is absent")
    func unavailableAttachment() {
        let result = SimulatorTargetSelector.resolve(
            from: [],
            hasVisibleWindow: false,
            windowTitle: nil
        )
        guard case .unavailable = result else {
            Issue.record("Expected unavailable selection")
            return
        }
    }

    @Test("automatic attachment selects the sole visible target")
    func automaticAttachment() {
        let result = SimulatorTargetSelector.resolve(
            from: [record(name: "iPhone 16 Pro", udid: "A")],
            hasVisibleWindow: true,
            windowTitle: "iPhone 16 Pro"
        )
        guard case let .selected(device) = result else {
            Issue.record("Expected selected target")
            return
        }
        #expect(device.udid == "A")
    }

    @Test("automatic attachment reports ambiguity instead of choosing first")
    func ambiguousAutomaticAttachment() {
        let devices = [record(name: "iPhone 16 Pro", udid: "A"), record(name: "iPad Pro", udid: "B")]
        let result = SimulatorTargetSelector.resolve(
            from: devices,
            hasVisibleWindow: true,
            windowTitle: "Simulator"
        )
        guard case .ambiguous = result else {
            Issue.record("Expected ambiguous selection")
            return
        }
    }

    @Test("duplicate device names remain ambiguous")
    func duplicateNamesAreAmbiguous() {
        let devices = [
            record(name: "iPhone 16 Pro", udid: "A"),
            record(name: "iPhone 16 Pro", udid: "B"),
        ]
        let result = SimulatorTargetSelector.resolve(
            from: devices,
            hasVisibleWindow: true,
            windowTitle: "iPhone 16 Pro - iOS 26.0"
        )
        guard case .ambiguous = result else {
            Issue.record("Expected duplicate names to remain ambiguous")
            return
        }
    }

    private func record(name: String, udid: String) -> BootedSimulatorRecord {
        BootedSimulatorRecord(
            name: name,
            udid: udid,
            runtime: "iOS 26.0",
            deviceType: name,
            screenSize: nil,
            nativeResolution: nil,
            scale: nil,
            dataPath: nil,
            source: "test"
        )
    }
}
