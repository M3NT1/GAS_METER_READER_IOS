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
