import Foundation
import Testing
@testable import GlidexCore

@Suite("Glidex preferences")
struct GlidexPreferencesTests {
    @Test("preferences restore persistent user choices")
    func persistence() {
        let store = MemoryPreferencesStore()
        let preferences = GlidexPreferences(store: store)
        let expected = GlidexPreferenceValues(
            isEnabled: false,
            inputMode: .edge,
            borderVisibility: .strong,
            showsAnchorIndicator: false,
            showsActiveTouches: true,
            prefersAnchorLocked: true,
            requiresPointerOverSimulator: false
        )
        preferences.save(expected)
        #expect(preferences.load() == expected)
    }

    @Test("missing data uses an explicitly enabled startup policy")
    func defaults() {
        #expect(GlidexPreferences(store: MemoryPreferencesStore()).load() == .defaults)
        #expect(GlidexPreferenceValues.defaults.isEnabled)
        #expect(GlidexPreferenceValues.defaults.requiresPointerOverSimulator)
    }

    @Test("legacy touch indicator migrates to both independent indicators")
    func indicatorMigration() throws {
        let legacy = Data(#"{"isEnabled":false,"inputMode":"edge","borderVisibility":"strong","showsTouchIndicator":false}"#.utf8)
        let decoded = try JSONDecoder().decode(GlidexPreferenceValues.self, from: legacy)
        #expect(!decoded.isEnabled)
        #expect(decoded.inputMode == .edge)
        #expect(decoded.borderVisibility == .strong)
        #expect(!decoded.showsAnchorIndicator)
        #expect(!decoded.showsActiveTouches)
        #expect(decoded.requiresPointerOverSimulator)
    }
}

private final class MemoryPreferencesStore: GlidexPreferencesStoring {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func setData(_ value: Data?, forKey key: String) { values[key] = value }
}
