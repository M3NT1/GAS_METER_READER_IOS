import Foundation

protocol ReadingRepository: Sendable {}
protocol PhotoArchive: Sendable {}
protocol InferenceService: Sendable {}
protocol CredentialStore: Sendable {}
protocol HomeAssistantClient: Sendable {}
protocol TrainingService: Sendable {}

final class InMemoryReadingRepository: ReadingRepository, @unchecked Sendable {}
final class SwiftDataReadingRepository: ReadingRepository, @unchecked Sendable {}
final class LocalPhotoArchive: PhotoArchive, @unchecked Sendable {}
final class StubInferenceService: InferenceService, @unchecked Sendable {}
final class ONNXInferenceService: InferenceService, @unchecked Sendable {}
final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {}
final class URLSessionHomeAssistantClient: HomeAssistantClient, @unchecked Sendable {}
final class LocalTrainingService: TrainingService, @unchecked Sendable {}

struct AppContainer: Sendable {
    let readingRepository: any ReadingRepository
    let photoArchive: any PhotoArchive
    let inferenceService: any InferenceService
    let credentialStore: any CredentialStore
    let homeAssistantClient: any HomeAssistantClient
    let trainingService: any TrainingService

    static func live() -> AppContainer {
        AppContainer(
            readingRepository: SwiftDataReadingRepository(),
            photoArchive: LocalPhotoArchive(),
            inferenceService: ONNXInferenceService(),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService()
        )
    }
}
