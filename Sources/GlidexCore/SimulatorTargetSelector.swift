import Foundation

public enum SimulatorTargetSelection: Sendable {
    case unavailable
    case selected(BootedSimulatorRecord)
    case ambiguous
}

public enum SimulatorTargetSelector {
    public static func resolve(
        from devices: [BootedSimulatorRecord],
        hasVisibleWindow: Bool,
        windowTitle: String?
    ) -> SimulatorTargetSelection {
        guard hasVisibleWindow, !devices.isEmpty else { return .unavailable }
        if let selected = select(from: devices, windowTitle: windowTitle) {
            return .selected(selected)
        }
        return .ambiguous
    }

    public static func select(
        from devices: [BootedSimulatorRecord],
        windowTitle: String?
    ) -> BootedSimulatorRecord? {
        if let windowTitle,
           let match = devices.first(where: { windowTitle.localizedCaseInsensitiveContains($0.name) }) {
            return match
        }
        return devices.count == 1 ? devices.first : nil
    }
}
