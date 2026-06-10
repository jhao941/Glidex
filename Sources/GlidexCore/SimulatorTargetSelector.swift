import Foundation

public enum SimulatorTargetSelector {
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
