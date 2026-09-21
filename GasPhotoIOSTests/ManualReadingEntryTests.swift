import Foundation
import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class ManualReadingEntryTests: XCTestCase {
    func testPhotoLessReadingPersistedAndRetrieved() async throws {
        let container = try makeTestContainer()
        let reading = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: "gas_main",
            photoID: nil,
            capturedAt: .now,
            window: nil,
            proposal: nil,
            approvedDigits: "01820.500",
            status: .approvedLocal,
            modelVersion: nil,
            lastSyncError: nil
        )

        try await container.readingRepository.insert(reading)

        let fetched = try await container.readingRepository.reading(id: reading.id)
        XCTAssertNil(fetched.photoID)
        XCTAssertEqual(fetched.approvedDigits, "01820.500")
        XCTAssertEqual(fetched.status, .approvedLocal)
        XCTAssertEqual(fetched.meterID, "gas_main")

        let all = try await container.readingRepository.allReadings()
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all.first?.photoID)
    }

    func testDeletePhotoLessReadingSucceeds() async throws {
        let container = try makeTestContainer()
        let reading = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: "gas_main",
            photoID: nil,
            capturedAt: .now,
            window: nil,
            proposal: nil,
            approvedDigits: "01820.500",
            status: .approvedLocal,
            modelVersion: nil,
            lastSyncError: nil
        )

        try await container.readingRepository.insert(reading)
        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        XCTAssertEqual(vm.readings.count, 1)

        await vm.delete(reading: reading)
        XCTAssertEqual(vm.readings.count, 0)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.statusMessage, "Leolvasás törölve.")

        let inRepo = try await container.readingRepository.allReadings()
        XCTAssertEqual(inRepo.count, 0)
    }

    func testPhotoLessReadingProgressionValidation() throws {
        let meter = Meter.defaultGas
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_086_400) // +1 day

        let priorReading = MeterReading(
            id: UUID(),
            meterID: meter.id,
            photoID: UUID(),
            capturedAt: t0,
            approvedDigits: "01800.000",
            status: .synced
        )

        let allReadings = [priorReading]

        // 1. Decreasing value candidate (photoID == nil)
        let candidateDecreasing = MeterReading(
            id: UUID(),
            meterID: meter.id,
            photoID: nil,
            capturedAt: t1,
            status: .approvedLocal
        )
        let approvedDecreasing = try ReadingValidator.approvedDigits("01799.000", format: meter.format)

        XCTAssertThrowsError(
            try ReadingProgressionValidator.validate(
                candidate: candidateDecreasing,
                approved: approvedDecreasing,
                meter: meter,
                allReadings: allReadings
            )
        ) { error in
            guard case let ReadingProgressionError.decreasingValue(candidate, prior, _) = error else {
                XCTFail("Expected decreasingValue error, got \(error)")
                return
            }
            XCTAssertEqual(candidate, "1799.000")
            XCTAssertEqual(prior, "1800.000")
        }

        // 2. Valid forward progression candidate (photoID == nil)
        let candidateValid = MeterReading(
            id: UUID(),
            meterID: meter.id,
            photoID: nil,
            capturedAt: t1,
            status: .approvedLocal
        )
        let approvedValid = try ReadingValidator.approvedDigits("01850.250", format: meter.format)

        XCTAssertNoThrow(
            try ReadingProgressionValidator.validate(
                candidate: candidateValid,
                approved: approvedValid,
                meter: meter,
                allReadings: allReadings
            )
        )
    }

    func testConsumptionCalculatorWithMixedPhotoAndPhotoLessReadings() throws {
        let electricityMeter = Meter(
            id: "electricity_main",
            name: "Villanyóra",
            kind: .electricity,
            format: MeterFormat(integerDigits: 6, fractionalDigits: 0),
            recognition: .manual,
            isArchived: false
        )

        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day5 = Date(timeIntervalSince1970: 1_700_000_000 + 4 * 86_400)
        let day10 = Date(timeIntervalSince1970: 1_700_000_000 + 9 * 86_400)

        // Reading 1: With photo
        let r1 = MeterReading(
            id: UUID(),
            meterID: electricityMeter.id,
            photoID: UUID(),
            capturedAt: day1,
            approvedDigits: "010000",
            status: .approvedLocal
        )

        // Reading 2: Photo-less (manual entry)
        let r2 = MeterReading(
            id: UUID(),
            meterID: electricityMeter.id,
            photoID: nil,
            capturedAt: day5,
            approvedDigits: "010050",
            status: .approvedLocal
        )

        // Reading 3: With photo
        let r3 = MeterReading(
            id: UUID(),
            meterID: electricityMeter.id,
            photoID: UUID(),
            capturedAt: day10,
            approvedDigits: "010120",
            status: .approvedLocal
        )

        let intervals = try ConsumptionCalculator.intervals(
            readings: [r3, r1, r2], // intentionally unsorted
            meter: electricityMeter
        )

        XCTAssertEqual(intervals.count, 2)

        // Interval 1: Day 1 -> Day 5 (50 kWh)
        XCTAssertEqual(intervals[0].fromReadingID, r1.id)
        XCTAssertEqual(intervals[0].toReadingID, r2.id)
        XCTAssertEqual(intervals[0].amount, Decimal(50))

        // Interval 2: Day 5 -> Day 10 (70 kWh)
        XCTAssertEqual(intervals[1].fromReadingID, r2.id)
        XCTAssertEqual(intervals[1].toReadingID, r3.id)
        XCTAssertEqual(intervals[1].amount, Decimal(70))

        let total = intervals.reduce(Decimal.zero) { $0 + $1.amount }
        XCTAssertEqual(total, Decimal(120))
    }

    func testRegisterTrainingExampleRejectsPhotoLessReading() async throws {
        let container = try makeTestContainer()
        try await container.meterRepository.save(.defaultGas)

        let reading = MeterReading(
            id: UUID(),
            meterID: "gas_main",
            photoID: nil, // Photo-less reading
            capturedAt: .now,
            window: NormalizedRect(left: 0.2, top: 0.4, right: 0.8, bottom: 0.6),
            approvedDigits: "01889.542",
            status: .pendingSync
        )
        try await container.readingRepository.insert(reading)

        let vm = ReadingsHistoryViewModel(container: container)
        await vm.load()
        await vm.registerAsTrainingExample(reading: reading)

        XCTAssertEqual(vm.trainingCount, 0)
        XCTAssertEqual(vm.errorMessage, "Csak fotóval, kerettel és számértékkel rendelkező leolvasás menthető tanítómintaként.")
    }

    private func makeTestContainer() throws -> AppContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: PersistedMeterReading.self,
            PersistedMeter.self,
            PersistedTrainingExample.self,
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
            homeAssistantUsageSettings: InMemoryHomeAssistantUsageSettings(isEnabled: false)
        )
    }
}
