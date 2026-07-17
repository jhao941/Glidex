import Foundation

public enum SimulatorAttachmentDecision: Equatable, Sendable {
    case unavailable
    case ambiguous
    case keepCurrent
    case attach(SimulatorDisplayDescriptor, BootedSimulatorRecord)
    case switchHost(SimulatorDisplayDescriptor, BootedSimulatorRecord)
    case switchDevice(SimulatorDisplayDescriptor, BootedSimulatorRecord)
}

public enum SimulatorAttachmentPolicy {
    public static func decide(
        displays: [SimulatorDisplayDescriptor],
        devices: [BootedSimulatorRecord],
        targetingMode: SimulatorTargetingMode,
        pinnedUDID: String?,
        currentUDID: String?,
        currentDisplay: SimulatorDisplayDescriptor?,
        activatedOwnerPID: pid_t? = nil
    ) -> SimulatorAttachmentDecision {
        let eligibleDisplays: [SimulatorDisplayDescriptor]
        let eligibleDevices: [BootedSimulatorRecord]

        switch targetingMode {
        case .followFocus:
            if let activatedOwnerPID {
                eligibleDisplays = displays.filter { $0.ownerPID == activatedOwnerPID }
            } else {
                eligibleDisplays = displays
            }
            eligibleDevices = devices
        case .pinned:
            guard let pinnedUDID else { return .unavailable }
            eligibleDisplays = displays
            eligibleDevices = devices.filter {
                $0.udid.caseInsensitiveCompare(pinnedUDID) == .orderedSame
            }
        }

        switch SimulatorDisplaySelector.resolve(displays: eligibleDisplays, devices: eligibleDevices) {
        case .unavailable:
            return .unavailable
        case .ambiguous:
            return .ambiguous
        case let .selected(display, device):
            guard let currentUDID else { return .attach(display, device) }
            guard currentUDID.caseInsensitiveCompare(device.udid) == .orderedSame else {
                return .switchDevice(display, device)
            }
            if currentDisplay?.representsSameDisplay(as: display) == true {
                return .keepCurrent
            }
            return .switchHost(display, device)
        }
    }
}
