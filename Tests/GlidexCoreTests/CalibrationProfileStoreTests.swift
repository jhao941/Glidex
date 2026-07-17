import CoreGraphics
import Foundation
import Testing
@testable import GlidexCore

@Suite("Calibration profiles")
struct CalibrationProfileStoreTests {
    @Test("profiles are isolated by host device orientation and scale")
    func profileIsolation() {
        let storage = MemoryStorage()
        let store = CalibrationProfileStore(store: storage)
        let simulator = key(host: .legacySimulator, udid: "a", orientation: .portrait, scale: 80)
        let deviceHub = key(host: .deviceHub, udid: "a", orientation: .portrait, scale: 80)
        let landscape = key(host: .legacySimulator, udid: "a", orientation: .landscape, scale: 80)
        let adjustment = OverlayFrameAdjustment(
            originDelta: CGSize(width: 3, height: -2),
            sizeDelta: CGSize(width: 5, height: 7)
        )

        store.save(adjustment, for: simulator)

        #expect(store.adjustment(for: simulator) == adjustment)
        #expect(store.adjustment(for: deviceHub) == nil)
        #expect(store.adjustment(for: landscape) == nil)
        #expect(CalibrationProfileStore(store: storage).adjustment(for: simulator) == adjustment)
    }

    @Test("default adjustment removes a saved profile")
    func defaultRemovesProfile() {
        let storage = MemoryStorage()
        let store = CalibrationProfileStore(store: storage)
        let profile = key(host: .deviceHub, udid: "B", orientation: .portrait, scale: 100)
        store.save(
            OverlayFrameAdjustment(originDelta: CGSize(width: 1, height: 1)),
            for: profile
        )
        store.save(OverlayFrameAdjustment(), for: profile)
        #expect(store.adjustment(for: profile) == nil)
    }

    @Test("display geometry produces a stable normalized key")
    func geometryKey() {
        let profile = CalibrationProfileKey(
            hostKind: .deviceHub,
            deviceUDID: "abc",
            displayFrame: CGRect(x: 0, y: 0, width: 201, height: 437),
            nativeSize: SimulatorPointSize(width: 402, height: 874)
        )
        #expect(profile.deviceUDID == "ABC")
        #expect(profile.orientation == .portrait)
        #expect(profile.displayScalePercent == 50)
    }

    private func key(
        host: SimulatorDisplayHostKind,
        udid: String,
        orientation: SimulatorDisplayOrientation,
        scale: Int
    ) -> CalibrationProfileKey {
        CalibrationProfileKey(
            hostKind: host,
            deviceUDID: udid,
            orientation: orientation,
            displayScalePercent: scale
        )
    }
}

private final class MemoryStorage: GlidexPreferencesStoring {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func setData(_ value: Data?, forKey key: String) { values[key] = value }
}
