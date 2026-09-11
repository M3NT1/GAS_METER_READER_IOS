@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CaptureViewModel {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let repository: any ReadingRepository
    private let archive: any PhotoArchive
    private let inference: any ReadingInferenceService
    private let credentialStore: any CredentialStore
    private let homeAssistantClient: any HomeAssistantClient
    private var captureService: CameraCaptureService?

    var isConfigured = false
    var isCapturing = false
    var errorMessage: String?
    var review: (model: ReviewViewModel, photoURL: URL)?

    init(container: AppContainer) {
        repository = container.readingRepository
        archive = container.photoArchive
        inference = container.inferenceService
        credentialStore = container.credentialStore
        homeAssistantClient = container.homeAssistantClient
    }

    func configureAndStart() {
        guard !isConfigured else {
            if !session.isRunning { session.startRunning() }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.configureSession() }
                    else { self?.errorMessage = "A kameraengedély szükséges a fényképezéshez." }
                }
            }
        default:
            errorMessage = "A kameraengedély a Beállításokban kapcsolható be."
        }
    }

    func capture() async {
        guard let captureService else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let photo = try await captureService.captureAndStore()
            var reading = MeterReading(
                id: UUID(),
                revision: 0,
                meterID: "gas_main",
                photoID: photo.id,
                capturedAt: photo.capturedAt,
                window: nil,
                proposal: nil,
                approvedDigits: nil,
                status: .needsReview,
                modelVersion: "window-detector-best + digit-classifier-active",
                lastSyncError: nil
            )
            try await repository.insert(reading)

            let photoURL = try archive.url(for: photo)
            let recognition = try await inference.propose(imageURL: photoURL, manualWindow: nil)
            reading.window = recognition.window
            reading.proposal = recognition.proposal
            reading.status = recognition.proposal == nil ? .needsReview : .counterRecognized
            try await repository.update(reading, expectedRevision: 0)
            reading.revision = 1
            review = (
                ReviewViewModel(
                    reading: reading,
                    repository: repository,
                    credentialStore: credentialStore,
                    homeAssistantClient: homeAssistantClient
                ),
                photoURL
            )
            session.stopRunning()
        } catch {
            errorMessage = "A fénykép feldolgozása nem sikerült. Próbáld újra."
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            errorMessage = "A kamera nem készíthető elő ezen az eszközön."
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        captureService = CameraCaptureService(output: photoOutput, archive: archive)
        isConfigured = true
        session.startRunning()
    }
}
