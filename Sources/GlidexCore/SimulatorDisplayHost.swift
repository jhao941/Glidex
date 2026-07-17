import CoreGraphics
import Foundation

public enum SimulatorDisplayHostKind: String, Equatable, Sendable {
    case legacySimulator
    case deviceHub

    public init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.iphonesimulator":
            self = .legacySimulator
        case "com.apple.dt.Devices":
            self = .deviceHub
        default:
            return nil
        }
    }
}

public struct SimulatorDisplayDescriptor: Equatable, Sendable {
    public var hostKind: SimulatorDisplayHostKind
    public var ownerPID: pid_t
    public var windowFrame: CGRect
    public var contentFrame: CGRect
    public var windowTitle: String?
    public var deviceName: String?
    public var runtime: String?
    public var deviceUDID: String?
    public var developerDirectory: String?

    public init(
        hostKind: SimulatorDisplayHostKind,
        ownerPID: pid_t,
        windowFrame: CGRect,
        contentFrame: CGRect,
        windowTitle: String? = nil,
        deviceName: String? = nil,
        runtime: String? = nil,
        deviceUDID: String? = nil,
        developerDirectory: String? = nil
    ) {
        self.hostKind = hostKind
        self.ownerPID = ownerPID
        self.windowFrame = windowFrame
        self.contentFrame = contentFrame
        self.windowTitle = windowTitle
        self.deviceName = deviceName
        self.runtime = runtime
        self.deviceUDID = deviceUDID
        self.developerDirectory = developerDirectory
    }

    public func representsSameDisplay(as other: SimulatorDisplayDescriptor) -> Bool {
        guard hostKind == other.hostKind, ownerPID == other.ownerPID else { return false }
        if let deviceUDID, let otherUDID = other.deviceUDID {
            return deviceUDID.caseInsensitiveCompare(otherUDID) == .orderedSame
        }
        return windowTitle == other.windowTitle
    }

    public func hasGeometryChange(from other: SimulatorDisplayDescriptor) -> Bool {
        windowFrame != other.windowFrame || contentFrame != other.contentFrame
    }
}

public enum SimulatorDisplaySelection: Sendable {
    case unavailable
    case selected(SimulatorDisplayDescriptor, BootedSimulatorRecord)
    case ambiguous
}

public enum SimulatorDisplaySelector {
    public static func resolve(
        displays: [SimulatorDisplayDescriptor],
        devices: [BootedSimulatorRecord],
        activatedOwnerPID: pid_t
    ) -> SimulatorDisplaySelection {
        resolve(
            displays: displays.filter { $0.ownerPID == activatedOwnerPID },
            devices: devices
        )
    }

    public static func resolve(
        displays: [SimulatorDisplayDescriptor],
        devices: [BootedSimulatorRecord]
    ) -> SimulatorDisplaySelection {
        guard !displays.isEmpty, !devices.isEmpty else { return .unavailable }

        let exact = matchedPairs(displays: displays, devices: devices) { display, device in
            guard let udid = display.deviceUDID else { return false }
            return udid.caseInsensitiveCompare(device.udid) == .orderedSame
        }
        if exact.count == 1, let pair = exact.first {
            return .selected(pair.0, pair.1)
        }
        if exact.count > 1 { return .ambiguous }

        let metadata = matchedPairs(displays: displays, devices: devices) { display, device in
            metadataMatches(display: display, device: device)
        }
        if metadata.count == 1, let pair = metadata.first {
            return .selected(pair.0, pair.1)
        }
        if metadata.count > 1 { return .ambiguous }

        if displays.count == 1, devices.count == 1,
           let display = displays.first, let device = devices.first {
            return .selected(display, device)
        }
        return .ambiguous
    }

    private static func matchedPairs(
        displays: [SimulatorDisplayDescriptor],
        devices: [BootedSimulatorRecord],
        predicate: (SimulatorDisplayDescriptor, BootedSimulatorRecord) -> Bool
    ) -> [(SimulatorDisplayDescriptor, BootedSimulatorRecord)] {
        displays.flatMap { display in
            devices.compactMap { device in predicate(display, device) ? (display, device) : nil }
        }
    }

    private static func metadataMatches(
        display: SimulatorDisplayDescriptor,
        device: BootedSimulatorRecord
    ) -> Bool {
        let nameMatches = [display.deviceName, display.windowTitle]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(device.name) }
        guard nameMatches else { return false }
        guard let runtime = display.runtime else { return true }
        return normalizedRuntime(runtime) == normalizedRuntime(device.runtime)
    }

    private static func normalizedRuntime(_ value: String) -> String {
        value.lowercased().filter { $0.isNumber || $0 == "." }
    }
}
