import Foundation
import SwiftData

protocol ReadingInferenceService: Sendable {
    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)?
    ) async throws -> RecognitionResult

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?
    ) async throws -> RecognitionResult
}

extension ReadingInferenceService {
    func propose(imageURL: URL, manualWindow: NormalizedRect?) async throws -> RecognitionResult {
        try await propose(imageURL: imageURL, manualWindow: manualWindow, onProgress: nil)
    }

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)?
    ) async throws -> RecognitionResult {
        try await propose(imageURL: imageURL, manualWindow: manualWindow)
    }
}

final class StubInferenceService: ReadingInferenceService, @unchecked Sendable {
    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)? = nil
    ) async throws -> RecognitionResult {
        onProgress?(.detectingWindow)
        onProgress?(.classifyingDigits(window: manualWindow))
        return RecognitionResult(window: manualWindow, proposal: nil, decimalReviewPositions: [])
    }
}

final class ONNXInferenceService: ReadingInferenceService, @unchecked Sendable {
    private let service: InferenceService

    init() throws {
        let runtime = try ONNXRuntime(paths: ModelBundle.inferenceModelPaths())
        service = InferenceService(runtime: runtime)
    }

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)? = nil
    ) async throws -> RecognitionResult {
        try await service.propose(imageURL: imageURL, manualWindow: manualWindow, onProgress: onProgress)
    }
}

@MainActor
struct AppContainer {
    let readingRepository: any ReadingRepository
    let photoArchive: any PhotoArchive
    let inferenceService: any ReadingInferenceService
    let trainingExampleStore: any TrainingExampleStore
    let credentialStore: any CredentialStore
    let homeAssistantClient: any HomeAssistantClient
    let trainingService: any TrainingService

    static func live() -> AppContainer {
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: PersistedMeterReading.self, PersistedTrainingExample.self)
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
            trainingExampleStore: SwiftDataTrainingExampleStore(modelContainer: modelContainer),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService()
        )
    }
}
