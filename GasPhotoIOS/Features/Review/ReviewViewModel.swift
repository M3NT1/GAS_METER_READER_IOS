import Foundation
import Observation

@MainActor
@Observable
final class ReviewViewModel {
    private let repository: any ReadingRepository
    private let credentialStore: (any CredentialStore)?
    private let homeAssistantClient: (any HomeAssistantClient)?
    private let trainingExampleStore: (any TrainingExampleStore)?
    private let inferenceService: (any ReadingInferenceService)?
    private let photoURL: URL?
    private(set) var reading: MeterReading
    private(set) var lastError: String?
    private(set) var isAnalyzingWindow: Bool = false

    var status: ReadingStatus { reading.status }

    init(
        reading: MeterReading,
        repository: any ReadingRepository,
        credentialStore: (any CredentialStore)? = nil,
        homeAssistantClient: (any HomeAssistantClient)? = nil,
        trainingExampleStore: (any TrainingExampleStore)? = nil,
        inferenceService: (any ReadingInferenceService)? = nil,
        photoURL: URL? = nil
    ) {
        self.reading = reading
        self.repository = repository
        self.credentialStore = credentialStore
        self.homeAssistantClient = homeAssistantClient
        self.trainingExampleStore = trainingExampleStore
        self.inferenceService = inferenceService
        self.photoURL = photoURL
    }

    func canApprove(displayDigits: String) -> Bool {
        (try? ReadingValidator.approvedDigits(displayDigits)) != nil
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
            approved = try ReadingValidator.approvedDigits(displayDigits)
        } catch {
            lastError = "A megadott érték nem jóváhagyható: pontosan 8 számjegy szükséges (5 egész + 3 tizedes)."
            return
        }

        if let progressionError = await validateProgression(uploadValue: approved.uploadValue) {
            lastError = progressionError
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
        updated.status = .pendingSync
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
        await syncApprovedReading()
    }

    func syncApprovedReading() async {
        guard reading.status == .pendingSync || reading.approvedDigits != nil,
              let credentialStore,
              let homeAssistantClient else { return }

        if let latest = try? await repository.reading(id: reading.id) {
            reading = latest
        }

        if let approvedDigits = reading.approvedDigits,
           let approved = try? ReadingValidator.approvedDigits(approvedDigits),
           let progressionError = await validateProgression(uploadValue: approved.uploadValue) {
            lastError = progressionError
            return
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

    private func validateProgression(uploadValue: String) async -> String? {
        guard let currentVal = Double(uploadValue),
              let allReadings = try? await repository.allReadings() else {
            return nil
        }
        let otherReadings = allReadings.filter {
            $0.id != reading.id && ($0.status == .synced || $0.approvedDigits != nil)
        }

        // Korábbi időpontban rögzített leolvasások
        let earlierReadings = otherReadings.filter { $0.capturedAt <= reading.capturedAt }
        if let latestPrior = earlierReadings.max(by: { $0.capturedAt < $1.capturedAt }),
           let priorDigits = latestPrior.approvedDigits,
           let priorApproved = try? ReadingValidator.approvedDigits(priorDigits),
           let priorVal = Double(priorApproved.uploadValue),
           currentVal < priorVal {
            return "A megadott állás (\(uploadValue) m³) kisebb, mint a korábbi rögzített állás (\(priorApproved.uploadValue) m³). A gázóra számlálója nem csökkenhet visszafelé! Ellenőrizd a beírt számjegyeket."
        }

        // Későbbi időpontban rögzített leolvasások
        let laterReadings = otherReadings.filter { $0.capturedAt >= reading.capturedAt }
        if let earliestLater = laterReadings.min(by: { $0.capturedAt < $1.capturedAt }),
           let laterDigits = earliestLater.approvedDigits,
           let laterApproved = try? ReadingValidator.approvedDigits(laterDigits),
           let laterVal = Double(laterApproved.uploadValue),
           currentVal > laterVal {
            return "A megadott állás (\(uploadValue) m³) nagyobb, mint a későbbi rögzített állás (\(laterApproved.uploadValue) m³). Ellenőrizd a dátumot vagy a számjegyeket!"
        }

        return nil
    }

    private func recordTrainingExampleIfPossible() async {
        guard let trainingExampleStore,
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
            photoID: reading.photoID,
            window: window,
            digits: digits,
            decision: decision,
            createdAt: .now
        )
        try? await trainingExampleStore.record(example)
    }
}
