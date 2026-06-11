import Foundation
import Testing
@testable import GlidexCore

@Suite("Simulator display hosts")
struct SimulatorDisplayHostTests {
    @Test("Device Hub CoreDevice ID exactly selects the booted simulator")
    func deviceHubUDIDMatch() {
        let display = descriptor(host: .deviceHub, pid: 10, udid: "B")
        let result = SimulatorDisplaySelector.resolve(
            displays: [display],
            devices: [record(name: "iPhone 17 Pro", udid: "A"), record(name: "iPad Pro", udid: "B")]
        )
        guard case let .selected(selectedDisplay, device) = result else {
            Issue.record("Expected an exact Device Hub selection")
            return
        }
        #expect(selectedDisplay.hostKind == .deviceHub)
        #expect(device.udid == "B")
    }

    @Test("an exact host wins when Device Hub and legacy Simulator coexist")
    func exactHostWins() {
        let displays = [
            descriptor(host: .deviceHub, pid: 10, udid: "B"),
            descriptor(host: .legacySimulator, pid: 20, title: "iPhone 17 Pro"),
        ]
        let result = SimulatorDisplaySelector.resolve(
            displays: displays,
            devices: [record(name: "iPhone 17 Pro", udid: "B")]
        )
        guard case let .selected(display, _) = result else {
            Issue.record("Expected exact Device Hub host")
            return
        }
        #expect(display.hostKind == .deviceHub)
    }

    @Test("coexisting hosts without an exact identity remain ambiguous")
    func coexistingHostsAreAmbiguous() {
        let displays = [
            descriptor(host: .deviceHub, pid: 10, title: "iPhone 17 Pro"),
            descriptor(host: .legacySimulator, pid: 20, title: "iPhone 17 Pro"),
        ]
        let result = SimulatorDisplaySelector.resolve(
            displays: displays,
            devices: [record(name: "iPhone 17 Pro", udid: "B")]
        )
        guard case .ambiguous = result else {
            Issue.record("Expected ambiguous coexisting hosts")
            return
        }
    }

    @Test("a rebuilt AX element retains identity and reports geometry changes")
    func rebuiltElementGeometry() {
        let old = descriptor(host: .deviceHub, pid: 10, udid: "B", frame: CGRect(x: 10, y: 20, width: 300, height: 650))
        let rebuilt = descriptor(host: .deviceHub, pid: 10, udid: "B", frame: CGRect(x: 40, y: 50, width: 360, height: 780))
        #expect(rebuilt.representsSameDisplay(as: old))
        #expect(rebuilt.hasGeometryChange(from: old))
    }

    @Test("host Xcode takes precedence when resolving SimulatorKit")
    func hostDeveloperDirectoryWins() {
        let betaKit = "/Applications/Xcode-beta.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit"
        let resolver = DeveloperDirectoryResolver(
            fileExists: { $0 == betaKit },
            selectedDeveloperDirectory: { "/Applications/Xcode.app/Contents/Developer" }
        )
        let result = resolver.resolve(
            hostBundleURL: URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app")
        )
        #expect(result?.developerDirectory == "/Applications/Xcode-beta.app/Contents/Developer")
        #expect(result?.simulatorKitPath == betaKit)
    }

    @Test("a loaded SimulatorKit cannot switch Xcode roots in one process")
    func loadedFrameworkSwitchIsRejected() {
        #expect(SimulatorKitFrameworkSwitch.decide(
            loadedPath: "/Xcode-beta/SimulatorKit",
            requestedPath: "/Xcode-beta/SimulatorKit"
        ) == .alreadySelected)
        #expect(SimulatorKitFrameworkSwitch.decide(
            loadedPath: nil,
            requestedPath: "/Xcode/SimulatorKit"
        ) == .useRequested)
        #expect(SimulatorKitFrameworkSwitch.decide(
            loadedPath: "/Xcode-beta/SimulatorKit",
            requestedPath: "/Xcode/SimulatorKit"
        ) == .incompatibleLoadedFramework("/Xcode-beta/SimulatorKit"))
    }

    private func descriptor(
        host: SimulatorDisplayHostKind,
        pid: pid_t,
        title: String? = nil,
        udid: String? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 300, height: 650)
    ) -> SimulatorDisplayDescriptor {
        SimulatorDisplayDescriptor(
            hostKind: host,
            ownerPID: pid,
            windowFrame: frame.insetBy(dx: -20, dy: -50),
            contentFrame: frame,
            windowTitle: title,
            deviceUDID: udid
        )
    }

    private func record(name: String, udid: String) -> BootedSimulatorRecord {
        BootedSimulatorRecord(
            name: name,
            udid: udid,
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceType: name,
            screenSize: nil,
            nativeResolution: nil,
            scale: nil,
            dataPath: nil,
            source: "test"
        )
    }
}
