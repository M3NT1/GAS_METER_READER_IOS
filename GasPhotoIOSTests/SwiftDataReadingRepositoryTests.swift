import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class SwiftDataReadingRepositoryTests: XCTestCase {
    func testUpdateIncrementsRevisionOnlyWhenExpectedRevisionMatches() async throws {
        let repository = try makeRepository()
        let original = makeReading(revision: 0)
        try await repository.insert(original)

        var approved = try await repository.reading(id: original.id)
        approved.approvedDigits = "01817.759"
        approved.status = .pendingSync
        try await repository.update(approved, expectedRevision: 0)

        let stored = try await repository.reading(id: original.id)
        XCTAssertEqual(stored.revision, 1)
        XCTAssertEqual(stored.approvedDigits, "01817.759")
        await XCTAssertThrowsErrorAsync {
            try await repository.update(approved, expectedRevision: 0)
        }
    }

    private func makeRepository() throws -> SwiftDataReadingRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PersistedMeterReading.self,
            configurations: configuration
        )
        return SwiftDataReadingRepository(modelContainer: container)
    }

    private func makeReading(revision: Int) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: revision,
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
