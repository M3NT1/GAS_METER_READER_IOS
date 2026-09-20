import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class MeterRepositoryTests: XCTestCase {
    func testRepositoryReturnsMetersSortedByNameAndPreservesArchivedState() async throws {
        let repository = InMemoryMeterRepository()
        let water = Meter(
            id: "water-garden",
            name: "Kerti vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: true
        )
        let gas = Meter(
            id: "gas_main",
            name: "Gázóra",
            kind: .gas,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .legacyGas8,
            isArchived: false
        )

        try await repository.save(water)
        try await repository.save(gas)

        let all = try await repository.allMeters()
        let storedWater = try await repository.meter(id: "water-garden")
        XCTAssertEqual(all.map(\.id), ["gas_main", "water-garden"])
        XCTAssertTrue(storedWater.isArchived)
    }

    func testBootstrapCreatesLegacyGasMeterOnlyOnce() async throws {
        let repository = InMemoryMeterRepository()
        let readings = [
            makeReading(meterID: "gas_main"),
            makeReading(meterID: "gas_main")
        ]

        try await MeterCatalogBootstrap.run(readings: readings, meters: repository)
        try await MeterCatalogBootstrap.run(readings: readings, meters: repository)

        let all = try await repository.allMeters()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.recognition, .legacyGas8)
        XCTAssertFalse(all.first?.isArchived ?? true)
    }

    func testBootstrapPreservesUnknownLegacyMeterAsArchivedManualGasMeter() async throws {
        let repository = InMemoryMeterRepository()

        try await MeterCatalogBootstrap.run(
            readings: [makeReading(meterID: "legacy-meter")],
            meters: repository
        )

        let meter = try await repository.meter(id: "legacy-meter")
        XCTAssertEqual(meter.kind, .gas)
        XCTAssertEqual(meter.recognition, .manual)
        XCTAssertTrue(meter.isArchived)
    }

    func testContainerBootstrapUsesPersistedReadings() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: PersistedMeterReading.self,
            PersistedMeter.self,
            configurations: configuration
        )
        let container = AppContainer(
            readingRepository: SwiftDataReadingRepository(modelContainer: modelContainer),
            meterRepository: SwiftDataMeterRepository(modelContainer: modelContainer),
            photoArchive: LocalPhotoArchive(),
            inferenceService: StubInferenceService(),
            trainingExampleStore: InMemoryTrainingExampleStore(),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService(),
            homeAssistantUsageSettings: InMemoryHomeAssistantUsageSettings()
        )
        try await container.readingRepository.insert(makeReading(meterID: "gas_main"))

        try await container.bootstrapMeterCatalog()

        let storedMeter = try await container.meterRepository.meter(id: "gas_main")
        XCTAssertEqual(storedMeter.recognition, .legacyGas8)
    }

    func testExistingReadingStoreOpensWhenMeterModelIsAdded() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }
        let oldConfiguration = ModelConfiguration(
            "legacy",
            url: storeURL,
            cloudKitDatabase: .none
        )
        let oldContainer = try ModelContainer(
            for: PersistedMeterReading.self,
            PersistedTrainingExample.self,
            configurations: oldConfiguration
        )
        let oldRepository = SwiftDataReadingRepository(modelContainer: oldContainer)
        let oldReading = makeReading(meterID: "gas_main")
        try await oldRepository.insert(oldReading)

        let upgradedConfiguration = ModelConfiguration(
            "legacy",
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgradedContainer = try ModelContainer(
            for: PersistedMeterReading.self,
            PersistedTrainingExample.self,
            PersistedMeter.self,
            configurations: upgradedConfiguration
        )
        let upgradedRepository = SwiftDataReadingRepository(modelContainer: upgradedContainer)
        let restored = try await upgradedRepository.reading(id: oldReading.id)

        XCTAssertEqual(restored, oldReading)
    }

    private func makeReading(meterID: String) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: meterID,
            photoID: UUID(),
            capturedAt: .now,
            window: nil,
            proposal: nil,
            approvedDigits: nil,
            status: .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )
    }
}
