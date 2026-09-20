import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class CaptureMeterSelectionTests: XCTestCase {
    func testInitialSelectionDefaultsToGasMainIfAvailable() async throws {
        let container = try makeTestContainer()
        let gasMeter = Meter(
            id: "gas_main",
            name: "Fő gázóra",
            kind: .gas,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .legacyGas8,
            isArchived: false
        )
        let waterMeter = Meter(
            id: "water_main",
            name: "Fő vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        try await container.meterRepository.save(waterMeter)
        try await container.meterRepository.save(gasMeter)

        let vm = CaptureViewModel(container: container)
        await vm.loadMeters()

        XCTAssertEqual(vm.selectedMeterID, "gas_main")
        XCTAssertEqual(vm.currentSelectedMeter?.id, "gas_main")
    }

    func testCaptureTakesImmutableSnapshotOfSelectedMeter() async throws {
        let container = try makeTestContainer()
        let meterA = Meter(
            id: "meter_a",
            name: "Mérő A",
            kind: .electricity,
            format: MeterFormat(integerDigits: 6, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        let meterB = Meter(
            id: "meter_b",
            name: "Mérő B",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        try await container.meterRepository.save(meterA)
        try await container.meterRepository.save(meterB)

        let vm = CaptureViewModel(container: container)
        await vm.loadMeters()
        vm.selectedMeterID = "meter_a"

        let sampleData = try makeSampleJPEGData()
        await vm.importPhoto(data: sampleData)

        XCTAssertNotNil(vm.review)
        XCTAssertEqual(vm.review?.model.reading.meterID, "meter_a")
        XCTAssertEqual(vm.review?.model.meter.id, "meter_a")

        // Switch selection after capture: review model retains its original snapshot
        vm.selectedMeterID = "meter_b"
        XCTAssertEqual(vm.review?.model.reading.meterID, "meter_a")
        XCTAssertEqual(vm.review?.model.meter.id, "meter_a")
    }

    func testManualRecognitionProfileSkipsInference() async throws {
        let countingInference = CountingInferenceService()
        let container = try makeTestContainer(inferenceService: countingInference)
        let waterMeter = Meter(
            id: "water_main",
            name: "Vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        try await container.meterRepository.save(waterMeter)

        let vm = CaptureViewModel(container: container)
        await vm.loadMeters()
        vm.selectedMeterID = "water_main"

        let sampleData = try makeSampleJPEGData()
        await vm.importPhoto(data: sampleData)

        XCTAssertEqual(countingInference.proposeCallCount, 0, "Manual profile must skip inference entirely.")
        XCTAssertNil(vm.review?.model.reading.proposal)
        XCTAssertNil(vm.review?.model.reading.window)
        XCTAssertEqual(vm.review?.model.reading.status, .needsReview)
    }

    private func makeTestContainer(
        inferenceService: (any ReadingInferenceService)? = nil
    ) throws -> AppContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: PersistedMeterReading.self, PersistedTrainingExample.self, PersistedMeter.self,
            configurations: configuration
        )
        return AppContainer(
            readingRepository: SwiftDataReadingRepository(modelContainer: modelContainer),
            meterRepository: SwiftDataMeterRepository(modelContainer: modelContainer),
            photoArchive: LocalPhotoArchive(),
            inferenceService: inferenceService ?? StubInferenceService(),
            trainingExampleStore: SwiftDataTrainingExampleStore(modelContainer: modelContainer),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService(),
            homeAssistantUsageSettings: InMemoryHomeAssistantUsageSettings()
        )
    }

    private func makeSampleJPEGData() throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil),
              let context = CGContext(
                  data: nil,
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:06:18 22:43:42",
                kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
                kCGImagePropertyExifSubsecTimeOriginal: "865"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}

private final class CountingInferenceService: ReadingInferenceService, @unchecked Sendable {
    var proposeCallCount = 0

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)? = nil
    ) async throws -> RecognitionResult {
        proposeCallCount += 1
        return RecognitionResult(window: nil, proposal: nil, decimalReviewPositions: [])
    }
}
