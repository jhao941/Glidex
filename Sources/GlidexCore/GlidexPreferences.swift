import Foundation

public protocol GlidexPreferencesStoring {
    func data(forKey key: String) -> Data?
    func setData(_ value: Data?, forKey key: String)
}

extension UserDefaults: GlidexPreferencesStoring {
    public func setData(_ value: Data?, forKey key: String) {
        set(value, forKey: key)
    }
}

public final class GlidexPreferences {
    private static let key = "GlidexPreferences.v1"
    private let store: GlidexPreferencesStoring

    public init(store: GlidexPreferencesStoring = UserDefaults.standard) {
        self.store = store
    }

    public func load() -> GlidexPreferenceValues {
        guard let data = store.data(forKey: Self.key),
              let values = try? JSONDecoder().decode(GlidexPreferenceValues.self, from: data) else {
            return .defaults
        }
        return values
    }

    public func save(_ values: GlidexPreferenceValues) {
        store.setData(try? JSONEncoder().encode(values), forKey: Self.key)
    }
}
