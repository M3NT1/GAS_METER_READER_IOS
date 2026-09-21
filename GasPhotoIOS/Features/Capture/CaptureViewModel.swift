@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation
import UIKit

enum CapturePhase: Equatable {
    case idle
    case capturingPhoto
    case detectingWindow
    case recognizingDigits
    case completed

    var title: String {
        switch self {
        case .idle:
            return ""
        case .capturingPhoto:
            return "Fotó rögzítése és mentése..."
        case .detectingWindow:
            return "Számlálókeret keresése AI-val..."
        case .recognizingDigits:
            return "Számjegyek leolvasása..."
        case .completed:
            return "Sikeres felismerés!"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return ""
        case .capturingPhoto:
            return "camera.metering.matrix"
        case .detectingWindow:
            return "sparkles.rectangle.stack"
        case .recognizingDigits:
            return "number.square.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }
}

@MainActor
@Observable
final class CaptureViewModel {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    let container: AppContainer
    private let repository: any ReadingRepository
    private let archive: any PhotoArchive
    private let inference: any ReadingInferenceService
    private let credentialStore: any CredentialStore
    private let homeAssistantClient: any HomeAssistantClient
    private let trainingExampleStore: any TrainingExampleStore
    private var captureService: CameraCaptureService?

    private var videoDevice: AVCaptureDevice?
    var isConfigured = false
    var isCapturing = false
    var phase: CapturePhase = .idle
    var capturedPreviewImage: UIImage? = nil
    var errorMessage: String?
    var review: (model: ReviewViewModel, photoURL: URL?)?
    var readingsCount: Int = 0
    var availableMeters: [Meter] = []
    var selectedMeterID: String?

    var currentSelectedMeter: Meter? {
        availableMeters.first { $0.id == selectedMeterID }
    }

    func loadMeters() async {
        do {
            let all = try await container.meterRepository.allMeters()
            availableMeters = all.filter { !$0.isArchived }
            if selectedMeterID == nil || !availableMeters.contains(where: { $0.id == selectedMeterID }) {
                selectedMeterID = availableMeters.first(where: { $0.id == "gas_main" })?.id ?? availableMeters.first?.id
            }
        } catch {
            // Keep existing selection
        }
    }

    var zoomFactor: CGFloat = 1.0
    let minZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 5.0

    var isTorchAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }
    var isTorchOn: Bool = false

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return captureService == nil
        #else
        return false
        #endif
    }

    func toggleTorch() {
        guard let device = videoDevice ?? AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isTorchOn = false
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore torch error
        }
    }

    func setZoom(factor: CGFloat) {
        guard let device = videoDevice ?? AVCaptureDevice.default(for: .video) else { return }
        let clamped = min(max(factor, minZoomFactor), min(device.maxAvailableVideoZoomFactor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            // Ignore zoom error
        }
    }

    func focus(at devicePoint: CGPoint) {
        guard let device = videoDevice ?? AVCaptureDevice.default(for: .video) else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore focus error
        }
    }

    func retake() {
        review = nil
        errorMessage = nil
        capturedPreviewImage = nil
        phase = .idle
        if isConfigured && !session.isRunning {
            let captureSession = session
            Task.detached(priority: .userInitiated) {
                captureSession.startRunning()
            }
        }
    }

    init(container: AppContainer) {
        self.container = container
        self.repository = container.readingRepository
        self.archive = container.photoArchive
        self.inference = container.inferenceService
        self.credentialStore = container.credentialStore
        self.homeAssistantClient = container.homeAssistantClient
        self.trainingExampleStore = container.trainingExampleStore
    }

    func configureAndStart() {
        Task { [weak self] in
            await self?.loadMeters()
        }

        guard !isConfigured else {
            if !session.isRunning {
                let captureSession = session
                Task.detached(priority: .userInitiated) {
                    captureSession.startRunning()
                }
            }
            return
        }

        #if targetEnvironment(simulator)
        isConfigured = true
        errorMessage = nil
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let sampleData = (try? Self.generateSimulatorSamplePhoto()) ?? Data()
            if let photo = try? archive.storeOriginal(sampleData, suggestedExtension: "jpg") {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    await self?.capture()
                }
            }
            return
        }
        if AVCaptureDevice.default(for: .video) == nil {
            isConfigured = true
            errorMessage = nil
            if ProcessInfo.processInfo.arguments.contains("--auto-capture") {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    await self?.capture()
                }
            }
            return
        }
        #endif

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
        guard let selectedMeterID,
              let meterSnapshot = availableMeters.first(where: { $0.id == selectedMeterID }) else {
            errorMessage = "Válassz ki egy aktív mérőórát a fotózás előtt."
            return
        }

        isCapturing = true
        phase = .capturingPhoto
        defer {
            isCapturing = false
            phase = .idle
        }

        do {
            let photo: PhotoReference
            if let captureService {
                photo = try await captureService.captureAndStore()
            } else {
                #if targetEnvironment(simulator)
                let sampleData = try Self.generateSimulatorSamplePhoto()
                photo = try archive.storeOriginal(sampleData, suggestedExtension: "jpg")
                #else
                return
                #endif
            }

            let photoURL = try archive.url(for: photo)
            if let uiImg = UIImage(contentsOfFile: photoURL.path) {
                capturedPreviewImage = uiImg
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            var reading = MeterReading(
                id: UUID(),
                revision: 0,
                meterID: meterSnapshot.id,
                photoID: photo.id,
                capturedAt: photo.capturedAt,
                window: nil,
                proposal: nil,
                approvedDigits: nil,
                status: .needsReview,
                modelVersion: meterSnapshot.recognition == .legacyGas8 ? "window-detector-best + digit-classifier-active" : nil,
                lastSyncError: nil
            )
            try await repository.insert(reading)

            if meterSnapshot.recognition == .legacyGas8 {
                let recognition = try await inference.propose(imageURL: photoURL, manualWindow: nil) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch progress {
                        case .detectingWindow:
                            self.phase = .detectingWindow
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        case .classifyingDigits:
                            self.phase = .recognizingDigits
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                }
                reading.window = recognition.window
                reading.proposal = recognition.proposal
                reading.status = recognition.proposal == nil ? .needsReview : .counterRecognized
                try await repository.update(reading, expectedRevision: 0)
                reading.revision = 1
            }

            self.phase = .completed
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(350))

            review = (
                ReviewViewModel(
                    reading: reading,
                    meter: meterSnapshot,
                    repository: repository,
                    credentialStore: credentialStore,
                    homeAssistantClient: homeAssistantClient,
                    homeAssistantUsageSettings: container.homeAssistantUsageSettings,
                    trainingExampleStore: trainingExampleStore,
                    inferenceService: inference,
                    photoURL: photoURL,
                    displayImage: capturedPreviewImage
                ),
                photoURL
            )
            let captureSession = session
            Task.detached(priority: .userInitiated) {
                captureSession.stopRunning()
            }
            capturedPreviewImage = nil
            await refreshReadingsCount()
        } catch {
            errorMessage = "A fénykép feldolgozása nem sikerült. Próbáld újra."
            capturedPreviewImage = nil
        }
    }

    func refreshReadingsCount() async {
        readingsCount = (try? await repository.allReadings().count) ?? 0
    }

    func importPhoto(data: Data) async {
        guard let selectedMeterID,
              let meterSnapshot = availableMeters.first(where: { $0.id == selectedMeterID }) else {
            errorMessage = "Válassz ki egy aktív mérőórát a fotó beolvasása előtt."
            return
        }

        isCapturing = true
        phase = .capturingPhoto
        defer {
            isCapturing = false
            phase = .idle
        }

        do {
            let photo = try archive.storeOriginal(data, suggestedExtension: "jpg")
            let photoURL = try archive.url(for: photo)
            if let uiImg = UIImage(data: data) {
                capturedPreviewImage = uiImg
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            var reading = MeterReading(
                id: UUID(),
                revision: 0,
                meterID: meterSnapshot.id,
                photoID: photo.id,
                capturedAt: photo.capturedAt,
                window: nil,
                proposal: nil,
                approvedDigits: nil,
                status: .needsReview,
                modelVersion: meterSnapshot.recognition == .legacyGas8 ? "window-detector-best + digit-classifier-active" : nil,
                lastSyncError: nil
            )
            try await repository.insert(reading)

            if meterSnapshot.recognition == .legacyGas8 {
                let recognition = try await inference.propose(imageURL: photoURL, manualWindow: nil) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch progress {
                        case .detectingWindow:
                            self.phase = .detectingWindow
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        case .classifyingDigits:
                            self.phase = .recognizingDigits
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                }
                reading.window = recognition.window
                reading.proposal = recognition.proposal
                reading.status = recognition.proposal == nil ? .needsReview : .counterRecognized
                try await repository.update(reading, expectedRevision: 0)
                reading.revision = 1
            }

            self.phase = .completed
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(350))

            review = (
                ReviewViewModel(
                    reading: reading,
                    meter: meterSnapshot,
                    repository: repository,
                    credentialStore: credentialStore,
                    homeAssistantClient: homeAssistantClient,
                    homeAssistantUsageSettings: container.homeAssistantUsageSettings,
                    trainingExampleStore: trainingExampleStore,
                    inferenceService: inference,
                    photoURL: photoURL,
                    displayImage: capturedPreviewImage
                ),
                photoURL
            )
            let captureSession = session
            Task.detached(priority: .userInitiated) {
                captureSession.stopRunning()
            }
            capturedPreviewImage = nil
            await refreshReadingsCount()
        } catch {
            errorMessage = "A beolvasott fotó feldolgozása nem sikerült."
            capturedPreviewImage = nil
        }
    }

    func openReadingReview(reading: MeterReading) async {
        let photoURL: URL?
        if let photoID = reading.photoID {
            photoURL = try? archive.url(for: photoID)
        } else {
            photoURL = nil
        }
        let meter = try? await container.meterRepository.meter(id: reading.meterID)
        review = (
            ReviewViewModel(
                reading: reading,
                meter: meter,
                repository: repository,
                credentialStore: credentialStore,
                homeAssistantClient: homeAssistantClient,
                homeAssistantUsageSettings: container.homeAssistantUsageSettings,
                trainingExampleStore: trainingExampleStore,
                inferenceService: inference,
                photoURL: photoURL
            ),
            photoURL
        )
        let captureSession = session
        Task.detached(priority: .userInitiated) {
            captureSession.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            #if targetEnvironment(simulator)
            isConfigured = true
            errorMessage = nil
            return
            #else
            errorMessage = "A kamera nem készíthető elő ezen az eszközön."
            return
            #endif
        }
        self.videoDevice = device

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isSubjectAreaChangeMonitoringEnabled {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore focus configuration error
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        captureService = CameraCaptureService(output: photoOutput, archive: archive)
        isConfigured = true
        session.commitConfiguration()

        let captureSession = session
        Task.detached(priority: .userInitiated) {
            captureSession.startRunning()
        }
    }

    #if targetEnvironment(simulator)
    private static func generateSimulatorSamplePhoto() throws -> Data {
        let width = 960
        let height = 960
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.setFillColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        context.fill(CGRect(x: 100, y: 120, width: 760, height: 720))

        let windowRect = CGRect(x: 180, y: 380, width: 600, height: 180)
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        context.fill(windowRect)

        let rollerWidth: CGFloat = 600.0 / 8.0
        for i in 0..<8 {
            let rollerRect = CGRect(x: 180.0 + CGFloat(i) * rollerWidth + 2, y: 385, width: rollerWidth - 4, height: 170)
            if i < 5 {
                context.setFillColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)
            } else {
                context.setFillColor(red: 0.82, green: 0.15, blue: 0.15, alpha: 1.0)
            }
            context.fill(rollerRect)
        }

        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let dateString = formatter.string(from: now)
        let offsetFormatter = DateFormatter()
        offsetFormatter.dateFormat = "xxx"
        let offsetString = offsetFormatter.string(from: now)

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: dateString,
                kCGImagePropertyExifOffsetTimeOriginal: offsetString,
                kCGImagePropertyExifSubsecTimeOriginal: "000"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
    #endif
}
