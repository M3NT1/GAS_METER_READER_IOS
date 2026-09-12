import XCTest
@testable import GasPhotoIOS

@MainActor
final class ReviewViewModelTests: XCTestCase {
    func testApproveDoesNotCreatePendingSyncWithoutEightDigits() async throws {
        let repository = InMemoryReadingRepository()
        let model = ReviewViewModel(reading: makeReading(), repository: repository)

        await model.approve(displayDigits: "1817.759")

        XCTAssertEqual(model.status, .needsReview)
        await XCTAssertThrowsErrorAsync {
            _ = try await repository.reading(id: model.reading.id)
        }
    }

    func testApproveRecordsManualCorrectionAsPendingSync() async throws {
        let repository = InMemoryReadingRepository()
        let model = ReviewViewModel(reading: makeReading(), repository: repository)

        await model.approve(displayDigits: "01817.759")

        let stored = try await repository.reading(id: model.reading.id)
        XCTAssertEqual(model.status, .pendingSync)
        XCTAssertEqual(stored.status, .pendingSync)
        XCTAssertEqual(stored.approvedDigits, "01817.759")
    }

    func testApproveUpdatesAnExistingCapturedReadingToPendingSync() async throws {
        let repository = InMemoryReadingRepository()
        let captured = makeReading()
        try await repository.insert(captured)
        let model = ReviewViewModel(reading: captured, repository: repository)

        await model.approve(displayDigits: "01817.759")

        let stored = try await repository.reading(id: captured.id)
        XCTAssertEqual(model.status, .pendingSync)
        XCTAssertEqual(model.reading.revision, 1)
        XCTAssertEqual(stored.revision, 1)
        XCTAssertEqual(stored.status, .pendingSync)
        XCTAssertEqual(stored.approvedDigits, "01817.759")
    }

    func testApprovalButtonEnablesOnlyForExactlyEightDigits() {
        let model = ReviewViewModel(reading: makeReading(), repository: InMemoryReadingRepository())

        XCTAssertFalse(model.canApprove(displayDigits: "1817.759"))
        XCTAssertTrue(model.canApprove(displayDigits: "01817.759"))
    }

    func testApproveRecordsCorrectedWindowedReadingAsTrainingExample() async throws {
        let repository = InMemoryReadingRepository()
        let trainingStore = InMemoryTrainingExampleStore()
        var reading = makeReading()
        reading.window = NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4)
        reading.proposal = DigitProposal(digits: "01817758", confidences: Array(repeating: 0.9, count: 8), uncertainPositions: [])
        let model = ReviewViewModel(
            reading: reading,
            repository: repository,
            trainingExampleStore: trainingStore
        )

        await model.approve(displayDigits: "01817.759")

        let example = try await trainingStore.example(readingID: reading.id)
        XCTAssertEqual(example?.digits, "01817.759")
        XCTAssertEqual(example?.decision, .corrected)
        XCTAssertEqual(example?.window, reading.window)
    }

    func testUpdateWindowReProposesDigitsWithInferenceService() async throws {
        let repository = InMemoryReadingRepository()
        let expectedResult = RecognitionResult(
            window: NormalizedRect(left: 0.2, top: 0.3, right: 0.8, bottom: 0.5),
            proposal: DigitProposal(digits: "02345678", confidences: Array(repeating: 0.95, count: 8), uncertainPositions: []),
            decimalReviewPositions: []
        )
        let mockInference = MockInferenceService(resultToReturn: expectedResult)
        let reading = makeReading()
        let model = ReviewViewModel(
            reading: reading,
            repository: repository,
            inferenceService: mockInference,
            photoURL: URL(fileURLWithPath: "/tmp/sample.jpg")
        )

        let newWindow = NormalizedRect(left: 0.2, top: 0.3, right: 0.8, bottom: 0.5)
        let formattedDigits = await model.updateWindow(newWindow)

        XCTAssertEqual(formattedDigits, "02345.678")
        XCTAssertEqual(model.reading.window, newWindow)
        XCTAssertEqual(model.reading.proposal?.digits, "02345678")
        XCTAssertEqual(model.status, .counterRecognized)
    }

    func testApproveWithExplicitWindowPersistsUpdatedWindow() async throws {
        let repository = InMemoryReadingRepository()
        let trainingStore = InMemoryTrainingExampleStore()
        let reading = makeReading()
        let model = ReviewViewModel(
            reading: reading,
            repository: repository,
            trainingExampleStore: trainingStore
        )

        let modifiedWindow = NormalizedRect(left: 0.25, top: 0.35, right: 0.75, bottom: 0.55)
        await model.approve(displayDigits: "01234.567", window: modifiedWindow)

        XCTAssertEqual(model.reading.window, modifiedWindow)
        let stored = try await repository.reading(id: reading.id)
        XCTAssertEqual(stored.window, modifiedWindow)
        let example = try await trainingStore.example(readingID: reading.id)
        XCTAssertEqual(example?.window, modifiedWindow)
    }

    private func makeReading() -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: "gas_main",
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

    func testApproveRejectsDecreasingReadingValueComparedToPriorReading() async throws {
        let repository = InMemoryReadingRepository()
        let earlierDate = Date(timeIntervalSince1970: 1_000_000)
        let laterDate = Date(timeIntervalSince1970: 2_000_000)

        // Prior reading: 1889.542
        var priorReading = makeReading()
        priorReading = MeterReading(
            id: UUID(),
            revision: 1,
            meterID: "gas_main",
            photoID: UUID(),
            capturedAt: earlierDate,
            window: nil,
            proposal: nil,
            approvedDigits: "01889.542",
            status: .synced,
            modelVersion: nil,
            lastSyncError: nil
        )
        try await repository.insert(priorReading)

        // New reading attempting 55.552: should be rejected
        let newReading = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: "gas_main",
            photoID: UUID(),
            capturedAt: laterDate,
            window: nil,
            proposal: nil,
            approvedDigits: nil,
            status: .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )
        let model = ReviewViewModel(reading: newReading, repository: repository)

        await model.approve(displayDigits: "00055.552")

        XCTAssertEqual(model.status, .needsReview)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(model.lastError?.contains("kisebb") == true)
        XCTAssertTrue(model.lastError?.contains("nem csökkenhet") == true)
    }
}

private final class MockInferenceService: ReadingInferenceService, @unchecked Sendable {
    let resultToReturn: RecognitionResult

    init(resultToReturn: RecognitionResult) {
        self.resultToReturn = resultToReturn
    }

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)? = nil
    ) async throws -> RecognitionResult {
        resultToReturn
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}
