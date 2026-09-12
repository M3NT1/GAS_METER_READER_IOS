import Foundation

@MainActor
final class InMemoryTrainingExampleStore: TrainingExampleStore {
    private var examples: [UUID: TrainingExample] = [:]

    func record(_ example: TrainingExample) async throws {
        examples[example.readingID] = example
    }

    func example(readingID: UUID) async throws -> TrainingExample? {
        examples[readingID]
    }

    func count() async throws -> Int {
        examples.count
    }

    func allExamples() async throws -> [TrainingExample] {
        examples.values.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(readingID: UUID) async throws {
        examples.removeValue(forKey: readingID)
    }
}
