import Foundation
import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class ReadingsHistoryViewModelTests: XCTestCase {
    func testLoadReadingsAndFilters() async throws {
        let container = try makeTestContainer()
        let reading1 = makeReading(status: .needsReview)
        let reading2 = makeReading(status: .pendingSync, approvedDigits: "01889.542")
        let reading3 = makeReading(status: .synced, approvedDigits: "01880.123")

        try await container.readingRepository.insert(reading1)
        try await container.readingRepository.insert(reading2)
        try await container.readingRepository.insert(reading3)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()

        XCTAssertEqual(vm.readings.count, 3)
        XCTAssertEqual(vm.pendingCount, 1)

        vm.selectedFilter = .pending
        XCTAssertEqual(vm.filteredReadings.count, 1)
        XCTAssertEqual(vm.filteredReadings.first?.id, reading2.id)

        vm.selectedFilter = .synced
        XCTAssertEqual(vm.filteredReadings.count, 1)
        XCTAssertEqual(vm.filteredReadings.first?.id, reading3.id)

        vm.selectedFilter = .needsReview
        XCTAssertEqual(vm.filteredReadings.count, 1)
        XCTAssertEqual(vm.filteredReadings.first?.id, reading1.id)
    }

    func testDeleteReadingRemovesFromStore() async throws {
        let container = try makeTestContainer()
        let reading = makeReading(status: .needsReview)
        try await container.readingRepository.insert(reading)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        XCTAssertEqual(vm.readings.count, 1)

        await vm.delete(reading: reading)
        XCTAssertEqual(vm.readings.count, 0)
        let inRepo = try await container.readingRepository.allReadings()
        XCTAssertEqual(inRepo.count, 0)
    }

    func testRegisterTrainingExampleSavesToStore() async throws {
        let container = try makeTestContainer()
        try await container.meterRepository.save(.defaultGas)
        let reading = makeReading(
            status: .pendingSync,
            window: NormalizedRect(left: 0.2, top: 0.4, right: 0.8, bottom: 0.6),
            approvedDigits: "01889.542"
        )
        try await container.readingRepository.insert(reading)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        XCTAssertEqual(vm.trainingCount, 0)

        await vm.registerAsTrainingExample(reading: reading)
        XCTAssertEqual(vm.trainingCount, 1)
        let storedExample = try await container.trainingExampleStore.example(readingID: reading.id)
        XCTAssertNotNil(storedExample)
        XCTAssertEqual(storedExample?.digits, "01889.542")
    }

    func testRegisterTrainingExampleRejectsManualMeter() async throws {
        let container = try makeTestContainer()
        let waterMeter = Meter(
            id: "water_main",
            name: "Vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 4, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        try await container.meterRepository.save(waterMeter)
        let reading = makeReading(
            meterID: "water_main",
            status: .approvedLocal,
            window: NormalizedRect(left: 0.2, top: 0.4, right: 0.8, bottom: 0.6),
            approvedDigits: "0123.456"
        )
        try await container.readingRepository.insert(reading)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        await vm.registerAsTrainingExample(reading: reading)

        XCTAssertEqual(vm.trainingCount, 0)
        XCTAssertEqual(vm.errorMessage, "Csak automatikus felismerésű gázóra menthető tanítómintaként.")
    }

    func testSyncBlocksWhenHomeAssistantDisabledOrMeterUnsupported() async throws {
        // Case 1: HA disabled
        let containerDisabled = try makeTestContainer(haEnabled: false)
        try await containerDisabled.meterRepository.save(.defaultGas)
        let gasReading = makeReading(status: .pendingSync, approvedDigits: "01889.542")
        try await containerDisabled.readingRepository.insert(gasReading)

        let vm1 = ReadingsHistoryViewModel(container: containerDisabled)
        await vm1.load()
        await vm1.sync(reading: gasReading)
        XCTAssertEqual(vm1.errorMessage, "A Home Assistant szinkronizálás ehhez a mérőhöz nem engedélyezett.")

        // Case 2: HA enabled, but meter is unsupported (e.g. manual water meter)
        let containerEnabled = try makeTestContainer(haEnabled: true)
        let waterMeter = Meter(
            id: "water_main",
            name: "Vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 4, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        try await containerEnabled.meterRepository.save(waterMeter)
        let waterReading = makeReading(meterID: "water_main", status: .approvedLocal, approvedDigits: "0123.456")
        try await containerEnabled.readingRepository.insert(waterReading)

        let vm2 = ReadingsHistoryViewModel(container: containerEnabled)
        await vm2.load()
        await vm2.sync(reading: waterReading)
        XCTAssertEqual(vm2.errorMessage, "A Home Assistant szinkronizálás ehhez a mérőhöz nem engedélyezett.")
    }

    func testSyncAllPendingBlocksWhenHomeAssistantDisabled() async throws {
        let container = try makeTestContainer(haEnabled: false)
        try await container.meterRepository.save(.defaultGas)
        let gasReading = makeReading(status: .pendingSync, approvedDigits: "01889.542")
        try await container.readingRepository.insert(gasReading)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        await vm.syncAllPending()
        XCTAssertEqual(vm.errorMessage, "A Home Assistant kapcsolat ki van kapcsolva.")
    }

    private func makeTestContainer(haEnabled: Bool = false) throws -> AppContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: PersistedMeterReading.self, PersistedTrainingExample.self, PersistedMeter.self,
            configurations: configuration
        )
        return AppContainer(
            readingRepository: SwiftDataReadingRepository(modelContainer: modelContainer),
            meterRepository: SwiftDataMeterRepository(modelContainer: modelContainer),
            photoArchive: LocalPhotoArchive(),
            inferenceService: StubInferenceService(),
            trainingExampleStore: SwiftDataTrainingExampleStore(modelContainer: modelContainer),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService(),
            homeAssistantUsageSettings: InMemoryHomeAssistantUsageSettings(isEnabled: haEnabled)
        )
    }

    private func makeReading(
        meterID: String = "gas_main",
        status: ReadingStatus,
        window: NormalizedRect? = nil,
        approvedDigits: String? = nil
    ) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: meterID,
            photoID: UUID(),
            capturedAt: .now,
            window: window,
            proposal: nil,
            approvedDigits: approvedDigits,
            status: status,
            modelVersion: nil,
            lastSyncError: nil
        )
    }
}
