import Foundation
import SwiftData

protocol ReadingInferenceService: Sendable {
    func propose(imageURL: URL, manualWindow: NormalizedRect?) async throws -> RecognitionResult
}
protocol CredentialStore: Sendable {}
protocol HomeAssistantClient: Sendable {}
protocol TrainingService: Sendable {}

final class StubInferenceService: ReadingInferenceService, @unchecked Sendable {
    func propose(imageURL: URL, manualWindow: NormalizedRect?) async throws -> RecognitionResult {
        RecognitionResult(window: nil, proposal: nil, decimalReviewPositions: [])
    }
}

final class ONNXInferenceService: ReadingInferenceService, @unchecked Sendable {
    private let service: InferenceService

    init() throws {
        let runtime = try ONNXRuntime(paths: ModelBundle.inferenceModelPaths())
        service = InferenceService(runtime: runtime)
    }

    func propose(imageURL: URL, manualWindow: NormalizedRect?) async throws -> RecognitionResult {
        try await service.propose(imageURL: imageURL, manualWindow: manualWindow)
    }
}
final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {}
final class URLSessionHomeAssistantClient: HomeAssistantClient, @unchecked Sendable {}
final class LocalTrainingService: TrainingService, @unchecked Sendable {}

@MainActor
struct AppContainer {
    let readingRepository: any ReadingRepository
    let photoArchive: any PhotoArchive
    let inferenceService: any ReadingInferenceService
    let credentialStore: any CredentialStore
    let homeAssistantClient: any HomeAssistantClient
    let trainingService: any TrainingService

    static func live() -> AppContainer {
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: PersistedMeterReading.self)
        } catch {
            fatalError("A helyi leolvasási napló nem indítható el.")
        }

        let inferenceService: ONNXInferenceService
        do {
            inferenceService = try ONNXInferenceService()
        } catch {
            fatalError("A helyi felismerőmodell nem indítható el.")
        }

        return AppContainer(
            readingRepository: SwiftDataReadingRepository(modelContainer: modelContainer),
            photoArchive: LocalPhotoArchive(),
            inferenceService: inferenceService,
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService()
        )
    }
}
