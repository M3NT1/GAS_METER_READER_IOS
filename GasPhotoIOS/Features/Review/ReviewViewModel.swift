import Foundation
import Observation

@MainActor
@Observable
final class ReviewViewModel {
    private let repository: any ReadingRepository
    private let credentialStore: (any CredentialStore)?
    private let homeAssistantClient: (any HomeAssistantClient)?
    private let trainingExampleStore: (any TrainingExampleStore)?
    private(set) var reading: MeterReading
    private(set) var lastError: String?

    var status: ReadingStatus { reading.status }

    init(
        reading: MeterReading,
        repository: any ReadingRepository,
        credentialStore: (any CredentialStore)? = nil,
        homeAssistantClient: (any HomeAssistantClient)? = nil,
        trainingExampleStore: (any TrainingExampleStore)? = nil
    ) {
        self.reading = reading
        self.repository = repository
        self.credentialStore = credentialStore
        self.homeAssistantClient = homeAssistantClient
        self.trainingExampleStore = trainingExampleStore
    }

    func canApprove(displayDigits: String) -> Bool {
        (try? ReadingValidator.approvedDigits(displayDigits)) != nil
    }

    func approve(displayDigits: String) async {
        do {
            let approved = try ReadingValidator.approvedDigits(displayDigits)
            var updated = reading
            updated.approvedDigits = approved.displayValue
            updated.status = .pendingSync
            updated.revision += 1

            do {
                try await repository.update(updated, expectedRevision: reading.revision)
            } catch ReadingRepositoryError.readingNotFound {
                updated.revision = reading.revision
                try await repository.insert(updated)
            }
            reading = updated
            lastError = nil
        } catch {
            lastError = "A megadott érték nem jóváhagyható."
            return
        }

        await recordTrainingExampleIfPossible()

        await syncApprovedReading()
    }

    func syncApprovedReading() async {
        guard reading.status == .pendingSync,
              let credentialStore,
              let homeAssistantClient else { return }

        do {
            guard let credentials = try await credentialStore.load() else { return }
            _ = try await homeAssistantClient.sync(reading: reading, credentials: credentials)
            var updated = reading
            updated.revision += 1
            updated.status = .synced
            updated.lastSyncError = nil
            try await repository.update(updated, expectedRevision: reading.revision)
            reading = updated
            lastError = nil
        } catch {
            lastError = "A Home Assistant feltöltés nem sikerült; a leolvasás a telefonon maradt."
        }
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
