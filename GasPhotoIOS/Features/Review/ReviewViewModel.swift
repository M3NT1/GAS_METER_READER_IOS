import Foundation
import ImageIO
import Observation
import UIKit

@MainActor
@Observable
final class ReviewViewModel {
    let meter: Meter
    private let repository: any ReadingRepository
    private let credentialStore: (any CredentialStore)?
    private let homeAssistantClient: (any HomeAssistantClient)?
    private let homeAssistantUsageSettings: (any HomeAssistantUsageSettings)?
    private let trainingExampleStore: (any TrainingExampleStore)?
    private let inferenceService: (any ReadingInferenceService)?
    private let photoURL: URL?
    private(set) var reading: MeterReading
    private(set) var lastError: String?
    private(set) var isAnalyzingWindow: Bool = false
    private(set) var displayImage: UIImage?
    private(set) var isLoadingDisplayImage: Bool = false
    private(set) var isSyncing: Bool = false

    var status: ReadingStatus { reading.status }

    init(
        reading: MeterReading,
        meter: Meter? = nil,
        repository: any ReadingRepository,
        credentialStore: (any CredentialStore)? = nil,
        homeAssistantClient: (any HomeAssistantClient)? = nil,
        homeAssistantUsageSettings: (any HomeAssistantUsageSettings)? = nil,
        trainingExampleStore: (any TrainingExampleStore)? = nil,
        inferenceService: (any ReadingInferenceService)? = nil,
        photoURL: URL? = nil,
        displayImage: UIImage? = nil
    ) {
        self.reading = reading
        self.meter = meter ?? Meter(
            id: reading.meterID,
            name: "Gázóra",
            kind: .gas,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .legacyGas8,
            isArchived: false
        )
        self.repository = repository
        self.credentialStore = credentialStore
        self.homeAssistantClient = homeAssistantClient
        self.homeAssistantUsageSettings = homeAssistantUsageSettings
        self.trainingExampleStore = trainingExampleStore
        self.inferenceService = inferenceService
        self.photoURL = photoURL
        self.displayImage = displayImage
        if displayImage == nil, let photoURL {
            loadDisplayImage(from: photoURL)
        }
    }

    private func loadDisplayImage(from url: URL) {
        isLoadingDisplayImage = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let loadedImage = Self.decodeDisplayThumbnail(at: url, maxPixelSize: 1600)
            await MainActor.run {
                guard let self else { return }
                self.displayImage = loadedImage
                self.isLoadingDisplayImage = false
            }
        }
    }

    nonisolated private static func decodeDisplayThumbnail(at url: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func canApprove(displayDigits: String) -> Bool {
        if meter.recognition == .legacyGas8 {
            return (try? ReadingValidator.approvedDigits(displayDigits)) != nil
        } else {
            return (try? ReadingValidator.approvedDigits(displayDigits, format: meter.format)) != nil
        }
    }

    @discardableResult
    func updateWindow(_ newWindow: NormalizedRect) async -> String? {
        var updated = reading
        updated.window = newWindow
        reading = updated

        guard let inferenceService, let photoURL else { return nil }
        isAnalyzingWindow = true
        defer { isAnalyzingWindow = false }

        do {
            let recognition = try await inferenceService.propose(imageURL: photoURL, manualWindow: newWindow)
            if let proposal = recognition.proposal {
                var updatedWithProposal = reading
                updatedWithProposal.proposal = proposal
                updatedWithProposal.status = .counterRecognized
                reading = updatedWithProposal
                if proposal.digits.count == 8 {
                    let index = proposal.digits.index(proposal.digits.startIndex, offsetBy: 5)
                    return String(proposal.digits[..<index]) + "." + String(proposal.digits[index...])
                }
            }
        } catch {
            // Keep existing proposal if inference fails
        }
        return nil
    }

    func approve(displayDigits: String, window: NormalizedRect? = nil) async {
        let approved: ApprovedReadingValue
        do {
            if meter.recognition == .legacyGas8 {
                approved = try ReadingValidator.approvedDigits(displayDigits)
            } else {
                approved = try ReadingValidator.approvedDigits(displayDigits, format: meter.format)
            }
        } catch {
            lastError = meter.recognition == .legacyGas8
                ? "A jóváhagyáshoz pontosan 8 számjegy szükséges."
                : "A megadott érték nem felel meg a mérőóra formátumának."
            return
        }

        let allReadings = (try? await repository.allReadings()) ?? []
        do {
            try ReadingProgressionValidator.validate(
                candidate: reading,
                approved: approved,
                meter: meter,
                allReadings: allReadings
            )
        } catch {
            lastError = error.localizedDescription
            return
        }

        if let latest = try? await repository.reading(id: reading.id) {
            reading = latest
        }

        var updated = reading
        if let window {
            updated.window = window
        }
        updated.approvedDigits = approved.displayValue
        let haEnabled = homeAssistantUsageSettings?.isEnabled ?? false
        if HomeAssistantSyncPolicy.mayStartRequest(enabled: haEnabled, meter: meter) {
            updated.status = .pendingSync
        } else {
            updated.status = .approvedLocal
        }
        updated.revision = reading.revision + 1

        do {
            try await repository.update(updated, expectedRevision: reading.revision)
            reading = (try? await repository.reading(id: reading.id)) ?? updated
            lastError = nil
        } catch ReadingRepositoryError.readingNotFound {
            updated.revision = reading.revision
            do {
                try await repository.insert(updated)
                reading = (try? await repository.reading(id: reading.id)) ?? updated
                lastError = nil
            } catch {
                lastError = "Mentési hiba: \(error.localizedDescription)"
                return
            }
        } catch ReadingRepositoryError.staleRevision {
            if let latest = try? await repository.reading(id: reading.id) {
                reading = latest
                updated.revision = latest.revision + 1
                try? await repository.update(updated, expectedRevision: latest.revision)
                reading = (try? await repository.reading(id: reading.id)) ?? updated
                lastError = nil
            }
        } catch {
            lastError = "Mentési hiba: \(error.localizedDescription)"
            return
        }

        await recordTrainingExampleIfPossible()
    }

    func syncApprovedReading() async {
        let haEnabled = homeAssistantUsageSettings?.isEnabled ?? false
        guard HomeAssistantSyncPolicy.mayStartRequest(enabled: haEnabled, meter: meter) else {
            lastError = "A Home Assistant szinkronizálás nem engedélyezett ehhez a mérőhöz."
            return
        }

        guard reading.status == .pendingSync || reading.approvedDigits != nil,
              let credentialStore,
              let homeAssistantClient else { return }

        isSyncing = true
        defer { isSyncing = false }

        if let latest = try? await repository.reading(id: reading.id) {
            reading = latest
        }

        if let approvedDigits = reading.approvedDigits,
           let approved = try? ReadingValidator.approvedDigits(approvedDigits, format: meter.format) {
            let allReadings = (try? await repository.allReadings()) ?? []
            do {
                try ReadingProgressionValidator.validate(
                    candidate: reading,
                    approved: approved,
                    meter: meter,
                    allReadings: allReadings
                )
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        do {
            guard let credentials = try await credentialStore.load() else {
                lastError = "Nincsenek megadva a Home Assistant beállítások."
                return
            }
            let verified = try await homeAssistantClient.sync(reading: reading, credentials: credentials)

            let current = (try? await repository.reading(id: reading.id)) ?? reading
            var updated = current
            updated.revision = max(current.revision, verified.revision) + 1
            updated.status = .synced
            updated.lastSyncError = nil

            do {
                try await repository.update(updated, expectedRevision: current.revision)
            } catch ReadingRepositoryError.staleRevision {
                if let latest = try? await repository.reading(id: reading.id) {
                    updated.revision = max(latest.revision, verified.revision) + 1
                    try? await repository.update(updated, expectedRevision: latest.revision)
                }
            }
            reading = (try? await repository.reading(id: reading.id)) ?? updated
            lastError = nil
        } catch {
            if let current = try? await repository.reading(id: reading.id) {
                var updated = current
                updated.lastSyncError = error.localizedDescription
                updated.revision = current.revision + 1
                try? await repository.update(updated, expectedRevision: current.revision)
                reading = (try? await repository.reading(id: reading.id)) ?? updated
            }
            lastError = "A Home Assistant feltöltés nem sikerült: \(error.localizedDescription)"
        }
    }

    private func recordTrainingExampleIfPossible() async {
        guard meter.recognition == .legacyGas8,
              let photoID = reading.photoID,
              let trainingExampleStore,
              let window = reading.window,
              let digits = reading.approvedDigits else { return }

        let proposedValue: String?
        if let proposal = reading.proposal, proposal.digits.count == 8 {
            let index = proposal.digits.index(proposal.digits.startIndex, offsetBy: 5)
            proposedValue = String(proposal.digits[..<index]) + "." + String(proposal.digits[index...])
        } else {
            proposedValue = nil
        }
        let decision: TrainingDecision = proposedValue == digits ? .approved : .corrected
        let example = TrainingExample(
            readingID: reading.id,
            photoID: photoID,
            window: window,
            digits: digits,
            decision: decision,
            createdAt: .now
        )
        try? await trainingExampleStore.record(example)
    }
}
