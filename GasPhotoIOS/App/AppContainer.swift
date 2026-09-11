import Foundation
import SwiftData

protocol ReadingInferenceService: Sendable {}
protocol CredentialStore: Sendable {}
protocol HomeAssistantClient: Sendable {}
protocol TrainingService: Sendable {}

final class StubInferenceService: ReadingInferenceService, @unchecked Sendable {}
final class ONNXInferenceService: ReadingInferenceService, @unchecked Sendable {}
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

        return AppContainer(
            readingRepository: SwiftDataReadingRepository(modelContainer: modelContainer),
            photoArchive: LocalPhotoArchive(),
            inferenceService: ONNXInferenceService(),
            credentialStore: KeychainCredentialStore(),
            homeAssistantClient: URLSessionHomeAssistantClient(),
            trainingService: LocalTrainingService()
        )
    }
}
