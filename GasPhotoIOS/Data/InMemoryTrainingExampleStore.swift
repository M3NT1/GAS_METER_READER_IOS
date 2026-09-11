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
}
