import CoreGraphics
import Foundation

public enum SimulatorDisplayOrientation: String, Codable, Equatable, Hashable, Sendable {
    case portrait
    case landscape
}

public struct CalibrationProfileKey: Codable, Equatable, Hashable, Sendable {
    public let hostKind: SimulatorDisplayHostKind
    public let deviceUDID: String
    public let orientation: SimulatorDisplayOrientation
    public let displayScalePercent: Int

    public init(
        hostKind: SimulatorDisplayHostKind,
        deviceUDID: String,
        orientation: SimulatorDisplayOrientation,
        displayScalePercent: Int
    ) {
        self.hostKind = hostKind
        self.deviceUDID = deviceUDID.uppercased()
        self.orientation = orientation
        self.displayScalePercent = max(1, displayScalePercent)
    }

    public init(
        hostKind: SimulatorDisplayHostKind,
        deviceUDID: String,
        displayFrame: CGRect,
        nativeSize: SimulatorPointSize
    ) {
        let orientation: SimulatorDisplayOrientation = displayFrame.width > displayFrame.height
            ? .landscape
            : .portrait
        let orientedSize = SimulatorDisplayGeometry.orientedSize(nativeSize, for: displayFrame.size)
        let widthScale = displayFrame.width / max(1, orientedSize.width)
        let heightScale = displayFrame.height / max(1, orientedSize.height)
        self.init(
            hostKind: hostKind,
            deviceUDID: deviceUDID,
            orientation: orientation,
            displayScalePercent: Int((min(widthScale, heightScale) * 100).rounded())
        )
    }
}

public final class CalibrationProfileStore {
    private struct Profile: Codable {
        let key: CalibrationProfileKey
        let adjustment: OverlayFrameAdjustment
    }

    private static let storageKey = "GlidexCalibrationProfiles.v1"
    private let store: GlidexPreferencesStoring

    public init(store: GlidexPreferencesStoring = UserDefaults.standard) {
        self.store = store
    }

    public func adjustment(for key: CalibrationProfileKey) -> OverlayFrameAdjustment? {
        profiles()[key]
    }

    public func save(_ adjustment: OverlayFrameAdjustment, for key: CalibrationProfileKey) {
        var values = profiles()
        if adjustment == OverlayFrameAdjustment() {
            values[key] = nil
        } else {
            values[key] = adjustment
        }
        let encoded = values
            .map { Profile(key: $0.key, adjustment: $0.value) }
            .sorted { lhs, rhs in
                let left = "\(lhs.key.hostKind.rawValue)|\(lhs.key.deviceUDID)|\(lhs.key.orientation.rawValue)|\(lhs.key.displayScalePercent)"
                let right = "\(rhs.key.hostKind.rawValue)|\(rhs.key.deviceUDID)|\(rhs.key.orientation.rawValue)|\(rhs.key.displayScalePercent)"
                return left < right
            }
        store.setData(try? JSONEncoder().encode(encoded), forKey: Self.storageKey)
    }

    public func removeAll() {
        store.setData(nil, forKey: Self.storageKey)
    }

    private func profiles() -> [CalibrationProfileKey: OverlayFrameAdjustment] {
        guard let data = store.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            return [:]
        }
        return Dictionary(decoded.map { ($0.key, $0.adjustment) }, uniquingKeysWith: { _, newest in newest })
    }
}
