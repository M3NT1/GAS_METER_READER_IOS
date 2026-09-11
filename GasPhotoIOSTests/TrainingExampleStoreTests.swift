import SwiftData
import XCTest
@testable import GasPhotoIOS

@MainActor
final class TrainingExampleStoreTests: XCTestCase {
    func testRecordKeepsOneLatestVerifiedExampleForEachReading() async throws {
        let store = try makeStore()
        let readingID = UUID()
        let original = TrainingExample(
            readingID: readingID,
            photoID: UUID(),
            window: NormalizedRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.4),
            digits: "01817.759",
            decision: .approved,
            createdAt: .now
        )
        try await store.record(original)
        var corrected = original
        corrected.digits = "01817.760"
        corrected.decision = .corrected
        try await store.record(corrected)

        let count = try await store.count()
        let stored = try await store.example(readingID: readingID)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(stored?.digits, "01817.760")
        XCTAssertEqual(stored?.decision, .corrected)
    }

    private func makeStore() throws -> SwiftDataTrainingExampleStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedTrainingExample.self, configurations: configuration)
        return SwiftDataTrainingExampleStore(modelContainer: container)
    }
}
