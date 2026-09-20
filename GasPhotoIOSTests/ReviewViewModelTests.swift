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
        let haSettings = InMemoryHomeAssistantUsageSettings(isEnabled: true)
        let model = ReviewViewModel(
            reading: makeReading(),
            repository: repository,
            homeAssistantUsageSettings: haSettings
        )

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
        let haSettings = InMemoryHomeAssistantUsageSettings(isEnabled: true)
        let model = ReviewViewModel(
            reading: captured,
            repository: repository,
            homeAssistantUsageSettings: haSettings
        )

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

    func testApproveLeavesReadingInPendingSyncAndExplicitSyncPushesToHomeAssistant() async throws {
        let repository = InMemoryReadingRepository()
        let credentials = try HomeAssistantCredentials(baseURL: "http://ha.local:8123", accessToken: "token123")
        let credentialStore = MockCredentialStore(credentials: credentials)
        let mockHAClient = MockHAClient()
        let haSettings = InMemoryHomeAssistantUsageSettings(isEnabled: true)
        let reading = makeReading()
        let model = ReviewViewModel(
            reading: reading,
            repository: repository,
            credentialStore: credentialStore,
            homeAssistantClient: mockHAClient,
            homeAssistantUsageSettings: haSettings
        )

        // Step 1: Approve saves locally in pendingSync, does NOT sync automatically
        await model.approve(displayDigits: "01826.811")
        XCTAssertEqual(model.status, .pendingSync)
        XCTAssertEqual(mockHAClient.syncCallsCount, 0)

        // Step 2: Explicit sync uploads to Home Assistant and transitions to synced
        await model.syncApprovedReading()
        XCTAssertEqual(model.status, .synced)
        XCTAssertEqual(mockHAClient.syncCallsCount, 1)
    }

    func testApproveWithDisabledHomeAssistantSavesAsApprovedLocalAndExplicitSyncDoesNotCallHA() async throws {
        let repository = InMemoryReadingRepository()
        let credentials = try HomeAssistantCredentials(baseURL: "http://ha.local:8123", accessToken: "token123")
        let credentialStore = MockCredentialStore(credentials: credentials)
        let mockHAClient = MockHAClient()
        let haSettings = InMemoryHomeAssistantUsageSettings(isEnabled: false)
        let reading = makeReading()
        let model = ReviewViewModel(
            reading: reading,
            repository: repository,
            credentialStore: credentialStore,
            homeAssistantClient: mockHAClient,
            homeAssistantUsageSettings: haSettings
        )

        // When HA is disabled, approve saves as approvedLocal and triggers 0 requests
        await model.approve(displayDigits: "01826.811")
        XCTAssertEqual(model.status, .approvedLocal)
        XCTAssertEqual(mockHAClient.syncCallsCount, 0)

        // Explicit sync also makes 0 requests
        await model.syncApprovedReading()
        XCTAssertEqual(model.status, .approvedLocal)
        XCTAssertEqual(mockHAClient.syncCallsCount, 0)
        XCTAssertNotNil(model.lastError)
    }

    func testApproveManualWaterMeterDoesNotRecordTrainingExample() async throws {
        let repository = InMemoryReadingRepository()
        let trainingStore = InMemoryTrainingExampleStore()
        let waterMeter = Meter(
            id: "water_main",
            name: "Fő vízóra",
            kind: .water,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        let reading = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: waterMeter.id,
            photoID: UUID(),
            capturedAt: .now,
            window: NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4),
            proposal: nil,
            approvedDigits: nil,
            status: .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )
        let model = ReviewViewModel(
            reading: reading,
            meter: waterMeter,
            repository: repository,
            trainingExampleStore: trainingStore
        )

        await model.approve(displayDigits: "00123.456")

        XCTAssertEqual(model.status, .approvedLocal)
        let example = try await trainingStore.example(readingID: reading.id)
        XCTAssertNil(example, "Manual meter must never record training examples")
    }

    func testApproveManualMeterFormatValidation() async throws {
        let repository = InMemoryReadingRepository()
        let elecMeter = Meter(
            id: "elec_main",
            name: "Villanyóra",
            kind: .electricity,
            format: MeterFormat(integerDigits: 6, fractionalDigits: 3),
            recognition: .manual,
            isArchived: false
        )
        let reading = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: elecMeter.id,
            photoID: UUID(),
            capturedAt: .now,
            window: nil,
            proposal: nil,
            approvedDigits: nil,
            status: .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )
        let model = ReviewViewModel(
            reading: reading,
            meter: elecMeter,
            repository: repository
        )

        // 6 digits integer + 3 fractional: "12,45" normalizes to "000012.450"
        await model.approve(displayDigits: "12,45")

        XCTAssertEqual(model.status, .approvedLocal)
        let stored = try await repository.reading(id: reading.id)
        XCTAssertEqual(stored.approvedDigits, "000012.450")
    }
}

private final class MockCredentialStore: CredentialStore, @unchecked Sendable {
    var credentials: HomeAssistantCredentials?
    init(credentials: HomeAssistantCredentials? = nil) { self.credentials = credentials }
    func load() async throws -> HomeAssistantCredentials? { credentials }
    func save(_ creds: HomeAssistantCredentials) async throws { credentials = creds }
    func clear() async throws { credentials = nil }
}

private final class MockHAClient: HomeAssistantClient, @unchecked Sendable {
    var syncCallsCount = 0
    func sync(reading: MeterReading, credentials: HomeAssistantCredentials) async throws -> HomeAssistantReading {
        syncCallsCount += 1
        return HomeAssistantReading(
            id: reading.id.uuidString,
            revision: reading.revision + 1,
            meterID: reading.meterID,
            value: reading.approvedDigits ?? "0",
            capturedAt: reading.capturedAt
        )
    }
    func testConnection(credentials: HomeAssistantCredentials) async throws -> ConnectionTestResult {
        ConnectionTestResult(isSuccess: true, message: "OK")
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
