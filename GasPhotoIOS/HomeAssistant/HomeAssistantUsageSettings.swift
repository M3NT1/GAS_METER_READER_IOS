import Foundation

@MainActor
protocol HomeAssistantUsageSettings: AnyObject {
    var isEnabled: Bool { get set }
    func initializeIfNeeded(hasCredentials: Bool)
}

@MainActor
final class UserDefaultsHomeAssistantUsageSettings: HomeAssistantUsageSettings {
    private enum Key {
        static let hasInitialized = "home_assistant_usage_initialized"
        static let isEnabled = "home_assistant_usage_enabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Key.isEnabled) }
        set { userDefaults.set(newValue, forKey: Key.isEnabled) }
    }

    func initializeIfNeeded(hasCredentials: Bool) {
        guard !userDefaults.bool(forKey: Key.hasInitialized) else { return }
        isEnabled = hasCredentials
        userDefaults.set(true, forKey: Key.hasInitialized)
    }
}
