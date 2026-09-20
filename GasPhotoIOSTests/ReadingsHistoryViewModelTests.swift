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

    private func makeTestContainer() throws -> AppContainer {
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
            trainingService: LocalTrainingService()
        )
    }

    private func makeReading(
        status: ReadingStatus,
        window: NormalizedRect? = nil,
        approvedDigits: String? = nil
    ) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: "gas_main",
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
