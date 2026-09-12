import XCTest
@testable import GasPhotoIOS

@MainActor
final class ModelTrainingViewModelTests: XCTestCase {
    func testPrerequisitesCheckWithZeroSamples() async throws {
        let store = InMemoryTrainingExampleStore()
        let service = LocalTrainingService()
        let viewModel = ModelTrainingViewModel(trainingExampleStore: store, trainingService: service)

        await viewModel.load()

        XCTAssertNotNil(viewModel.prerequisites)
        XCTAssertEqual(viewModel.prerequisites?.sampleCount, 0)
        XCTAssertFalse(viewModel.prerequisites?.hasEnoughSamples ?? true)
        XCTAssertFalse(viewModel.prerequisites?.unmetReasons.isEmpty ?? true)
    }

    func testPrerequisitesCheckWithFortySamples() async throws {
        let store = InMemoryTrainingExampleStore()
        let service = LocalTrainingService()

        for index in 0 ..< 40 {
            let example = TrainingExample(
                id: UUID(),
                readingID: UUID(),
                photoID: UUID(),
                window: NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4),
                digits: "0188954\(index % 10)",
                decision: .approved,
                createdAt: Date()
            )
            try await store.record(example)
        }

        let viewModel = ModelTrainingViewModel(trainingExampleStore: store, trainingService: service)
        await viewModel.load()

        XCTAssertEqual(viewModel.prerequisites?.sampleCount, 40)
        XCTAssertTrue(viewModel.prerequisites?.hasEnoughSamples ?? false)
    }

    func testStartTrainingProducesCandidateAndCanActivate() async throws {
        let store = InMemoryTrainingExampleStore()
        let service = LocalTrainingService()

        for index in 0 ..< 5 {
            let example = TrainingExample(
                id: UUID(),
                readingID: UUID(),
                photoID: UUID(),
                window: NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4),
                digits: "0188954\(index)",
                decision: .approved,
                createdAt: Date()
            )
            try await store.record(example)
        }

        let viewModel = ModelTrainingViewModel(trainingExampleStore: store, trainingService: service)
        await viewModel.load()

        XCTAssertNil(viewModel.candidateEvaluation)

        await viewModel.startTraining(allowSampleOverride: true)

        XCTAssertFalse(viewModel.isTraining)
        XCTAssertNotNil(viewModel.candidateEvaluation)
        guard let candidate = viewModel.candidateEvaluation else { return }

        XCTAssertTrue(candidate.isPassingGate)
        XCTAssertGreaterThan(candidate.candidateAccuracy, candidate.baselineAccuracy)
        XCTAssertEqual(candidate.regressionCount, 0)

        // Test activation
        await viewModel.activateCandidate()
        XCTAssertNil(viewModel.candidateEvaluation)
        XCTAssertEqual(viewModel.activeStatus?.type, .custom)
        XCTAssertTrue(viewModel.activeStatus?.version.contains("Saját modell") ?? false)

        // Test rollback
        await viewModel.rollbackToFactoryModel()
        XCTAssertEqual(viewModel.activeStatus?.type, .factory)
        XCTAssertTrue(viewModel.activeStatus?.version.contains("Gyári") ?? false)
    }

    func testCancelTraining() async throws {
        let store = InMemoryTrainingExampleStore()
        let service = LocalTrainingService()
        let viewModel = ModelTrainingViewModel(trainingExampleStore: store, trainingService: service)

        viewModel.isTraining = true
        viewModel.cancelTraining()

        XCTAssertFalse(viewModel.isTraining)
        XCTAssertNil(viewModel.progress)
    }
}
