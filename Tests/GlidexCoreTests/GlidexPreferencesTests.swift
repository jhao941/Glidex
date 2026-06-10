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
            showsTouchIndicator: false
        )
        preferences.save(expected)
        #expect(preferences.load() == expected)
    }

    @Test("missing data uses an explicitly enabled startup policy")
    func defaults() {
        #expect(GlidexPreferences(store: MemoryPreferencesStore()).load() == .defaults)
        #expect(GlidexPreferenceValues.defaults.isEnabled)
    }
}

private final class MemoryPreferencesStore: GlidexPreferencesStoring {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func setData(_ value: Data?, forKey key: String) { values[key] = value }
}
