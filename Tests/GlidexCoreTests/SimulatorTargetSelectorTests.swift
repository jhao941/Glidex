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
