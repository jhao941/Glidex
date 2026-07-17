import Foundation
import Testing
@testable import GlidexCore

@Suite("Simulator attachment policy")
struct SimulatorAttachmentPolicyTests {
    @Test("follow focus switches to the activated host and its device")
    func followsActivatedHost() {
        let current = descriptor(host: .legacySimulator, pid: 10, title: "iPhone A")
        let focused = descriptor(host: .deviceHub, pid: 20, udid: "B")
        let decision = SimulatorAttachmentPolicy.decide(
            displays: [current, focused],
            devices: [record(name: "iPhone A", udid: "A"), record(name: "iPad B", udid: "B")],
            targetingMode: .followFocus,
            pinnedUDID: nil,
            currentUDID: "A",
            currentDisplay: current,
            activatedOwnerPID: 20
        )
        guard case let .switchDevice(display, device) = decision else {
            Issue.record("Expected an atomic device switch decision")
            return
        }
        #expect(display == focused)
        #expect(device.udid == "B")
    }

    @Test("pinned targeting ignores the activated host")
    func pinnedIgnoresFocus() {
        let pinned = descriptor(host: .legacySimulator, pid: 10, title: "iPhone A")
        let focused = descriptor(host: .deviceHub, pid: 20, udid: "B")
        let decision = SimulatorAttachmentPolicy.decide(
            displays: [pinned, focused],
            devices: [record(name: "iPhone A", udid: "A"), record(name: "iPad B", udid: "B")],
            targetingMode: .pinned,
            pinnedUDID: "A",
            currentUDID: "A",
            currentDisplay: pinned,
            activatedOwnerPID: 20
        )
        #expect(decision == .keepCurrent)
    }

    @Test("same device on a different app is a host-only switch")
    func hostOnlySwitch() {
        let current = descriptor(host: .legacySimulator, pid: 10, title: "iPhone A")
        let focused = descriptor(host: .deviceHub, pid: 20, udid: "A")
        let device = record(name: "iPhone A", udid: "A")
        let decision = SimulatorAttachmentPolicy.decide(
            displays: [current, focused],
            devices: [device],
            targetingMode: .followFocus,
            pinnedUDID: nil,
            currentUDID: "A",
            currentDisplay: current,
            activatedOwnerPID: 20
        )
        #expect(decision == .switchHost(focused, device))
    }

    @Test("a missing pinned device cannot disturb the current attachment")
    func missingPinnedTarget() {
        let current = descriptor(host: .legacySimulator, pid: 10, title: "iPhone A")
        let decision = SimulatorAttachmentPolicy.decide(
            displays: [current],
            devices: [record(name: "iPhone A", udid: "A")],
            targetingMode: .pinned,
            pinnedUDID: "missing",
            currentUDID: "A",
            currentDisplay: current
        )
        #expect(decision == .unavailable)
    }

    private func descriptor(
        host: SimulatorDisplayHostKind,
        pid: pid_t,
        title: String? = nil,
        udid: String? = nil
    ) -> SimulatorDisplayDescriptor {
        SimulatorDisplayDescriptor(
            hostKind: host,
            ownerPID: pid,
            windowFrame: CGRect(x: 0, y: 0, width: 340, height: 700),
            contentFrame: CGRect(x: 20, y: 40, width: 300, height: 650),
            windowTitle: title,
            deviceUDID: udid
        )
    }

    private func record(name: String, udid: String) -> BootedSimulatorRecord {
        BootedSimulatorRecord(
            name: name,
            udid: udid,
            runtime: "iOS 27.0",
            deviceType: name,
            screenSize: nil,
            nativeResolution: nil,
            scale: nil,
            dataPath: nil,
            source: "test"
        )
    }
}
