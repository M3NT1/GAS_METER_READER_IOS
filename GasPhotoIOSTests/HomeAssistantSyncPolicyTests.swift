import XCTest
@testable import GasPhotoIOS

@MainActor
final class HomeAssistantSyncPolicyTests: XCTestCase {
    func testNewInstallationStartsWithHomeAssistantDisabled() {
        let defaults = makeDefaults()
        let settings = UserDefaultsHomeAssistantUsageSettings(userDefaults: defaults)

        settings.initializeIfNeeded(hasCredentials: false)

        XCTAssertFalse(settings.isEnabled)
    }

    func testExistingCredentialsEnableOnlyTheFirstInitialization() {
        let defaults = makeDefaults()
        let settings = UserDefaultsHomeAssistantUsageSettings(userDefaults: defaults)

        settings.initializeIfNeeded(hasCredentials: true)
        XCTAssertTrue(settings.isEnabled)

        settings.isEnabled = false
        let relaunchedSettings = UserDefaultsHomeAssistantUsageSettings(userDefaults: defaults)
        relaunchedSettings.initializeIfNeeded(hasCredentials: true)
        XCTAssertFalse(relaunchedSettings.isEnabled)
    }

    func testPolicyOnlySupportsTheExistingGasServerContract() {
        let legacyGas = Meter(
            id: "gas_main",
            name: "Gázóra",
            kind: .gas,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .legacyGas8,
            isArchived: false
        )
        let water = Meter(
            id: "water_main",
            name: "Vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )

        XCTAssertTrue(HomeAssistantSyncPolicy.supports(legacyGas))
        XCTAssertFalse(HomeAssistantSyncPolicy.supports(water))
        XCTAssertFalse(HomeAssistantSyncPolicy.mayStartRequest(enabled: false, meter: legacyGas))
        XCTAssertTrue(HomeAssistantSyncPolicy.mayStartRequest(enabled: true, meter: legacyGas))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HomeAssistantSyncPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
