import Foundation
import SwiftData

@MainActor
protocol TrainingExampleStore: AnyObject {
    func record(_ example: TrainingExample) async throws
    func example(readingID: UUID) async throws -> TrainingExample?
    func count() async throws -> Int
}

@Model
final class PersistedTrainingExample {
    @Attribute(.unique) var readingID: UUID
    var id: UUID
    var photoID: UUID
    var windowData: Data
    var digits: String
    var decisionRawValue: String
    var createdAt: Date

    init(example: TrainingExample) throws {
        readingID = example.readingID
        id = example.id
        photoID = example.photoID
        windowData = try JSONEncoder().encode(example.window)
        digits = example.digits
        decisionRawValue = example.decision.rawValue
        createdAt = example.createdAt
    }

    func replace(with example: TrainingExample) throws {
        id = example.id
        photoID = example.photoID
        windowData = try JSONEncoder().encode(example.window)
        digits = example.digits
        decisionRawValue = example.decision.rawValue
        createdAt = example.createdAt
    }

    func domainValue() throws -> TrainingExample {
        guard let decision = TrainingDecision(rawValue: decisionRawValue) else {
            throw ReadingRepositoryError.readingNotFound
        }
        return TrainingExample(
            id: id,
            readingID: readingID,
            photoID: photoID,
            window: try JSONDecoder().decode(NormalizedRect.self, from: windowData),
            digits: digits,
            decision: decision,
            createdAt: createdAt
        )
    }
}

@MainActor
final class SwiftDataTrainingExampleStore: TrainingExampleStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func record(_ example: TrainingExample) async throws {
        if let stored = try storedExample(readingID: example.readingID) {
            try stored.replace(with: example)
        } else {
            modelContext.insert(try PersistedTrainingExample(example: example))
        }
        try modelContext.save()
    }

    func example(readingID: UUID) async throws -> TrainingExample? {
        try storedExample(readingID: readingID)?.domainValue()
    }

    func count() async throws -> Int {
        try modelContext.fetch(FetchDescriptor<PersistedTrainingExample>()).count
    }

    private func storedExample(readingID: UUID) throws -> PersistedTrainingExample? {
        try modelContext.fetch(FetchDescriptor<PersistedTrainingExample>())
            .first { $0.readingID == readingID }
    }
}
