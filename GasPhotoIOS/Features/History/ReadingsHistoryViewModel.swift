import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ReadingsHistoryViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Összes"
        case pending = "Feltöltendő"
        case synced = "Szinkronizált"
        case needsReview = "Átnézendő"

        var id: String { rawValue }
    }

    let container: AppContainer
    private let repository: any ReadingRepository
    private let archive: any PhotoArchive
    private let credentialStore: any CredentialStore
    private let homeAssistantClient: any HomeAssistantClient
    private let trainingExampleStore: any TrainingExampleStore

    var readings: [MeterReading] = []
    var meters: [Meter] = []
    var selectedFilter: Filter = .all
    var isLoading = false
    var statusMessage: String?
    var errorMessage: String?
    var trainingCount: Int = 0

    var filteredReadings: [MeterReading] {
        switch selectedFilter {
        case .all:
            return readings
        case .pending:
            return readings.filter { $0.status == .pendingSync }
        case .synced:
            return readings.filter { $0.status == .synced }
        case .needsReview:
            return readings.filter { $0.status == .needsReview || $0.status == .positionIdentified || $0.status == .counterRecognized }
        }
    }

    var pendingCount: Int {
        readings.filter { $0.status == .pendingSync }.count
    }

    init(container: AppContainer) {
        self.container = container
        self.repository = container.readingRepository
        self.archive = container.photoArchive
        self.credentialStore = container.credentialStore
        self.homeAssistantClient = container.homeAssistantClient
        self.trainingExampleStore = container.trainingExampleStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            readings = try await repository.allReadings()
            meters = (try? await container.meterRepository.allMeters()) ?? []
            trainingCount = (try? await trainingExampleStore.count()) ?? 0
        } catch {
            errorMessage = "A leolvasások betöltése nem sikerült."
        }
    }

    func consumptionIntervals(for meter: Meter) throws -> [ConsumptionInterval] {
        try ConsumptionCalculator.intervals(readings: readings, meter: meter)
    }

    func delete(reading: MeterReading) async {
        do {
            try await repository.delete(id: reading.id)
            try? archive.delete(photoID: reading.photoID)
            try? await trainingExampleStore.delete(readingID: reading.id)
            readings.removeAll { $0.id == reading.id }
            trainingCount = (try? await trainingExampleStore.count()) ?? 0
            statusMessage = "Leolvasás törölve."
        } catch {
            errorMessage = "A leolvasás törlése nem sikerült."
        }
    }

    func sync(reading: MeterReading) async {
        guard reading.status == .pendingSync || reading.approvedDigits != nil else {
            errorMessage = "Csak jóváhagyott értéket lehet feltölteni."
            return
        }

        let meter = try? await container.meterRepository.meter(id: reading.meterID)
        guard let meter, HomeAssistantSyncPolicy.mayStartRequest(enabled: container.homeAssistantUsageSettings.isEnabled, meter: meter) else {
            errorMessage = "A Home Assistant szinkronizálás ehhez a mérőhöz nem engedélyezett."
            return
        }

        do {
            guard let credentials = try await credentialStore.load() else {
                errorMessage = "Nincsenek megadva a Home Assistant beállítások."
                return
            }
            let verified = try await homeAssistantClient.sync(reading: reading, credentials: credentials)
            var updated = reading
            updated.revision = max(updated.revision, verified.revision) + 1
            updated.status = .synced
            updated.lastSyncError = nil
            try await repository.update(updated, expectedRevision: reading.revision)
            if let idx = readings.firstIndex(where: { $0.id == reading.id }) {
                readings[idx] = updated
            }
            statusMessage = "Sikeres feltöltés a Home Assistantba!"
        } catch {
            errorMessage = "A Home Assistant feltöltés sikertelen: \(error.localizedDescription)"
        }
    }

    func syncAllPending() async {
        let pendings = readings.filter { $0.status == .pendingSync }
        guard !pendings.isEmpty else { return }

        guard container.homeAssistantUsageSettings.isEnabled else {
            errorMessage = "A Home Assistant kapcsolat ki van kapcsolva."
            return
        }

        guard let credentials = try? await credentialStore.load() else {
            errorMessage = "Nincsenek megadva a Home Assistant beállítások."
            return
        }

        var successCount = 0
        for reading in pendings {
            guard container.homeAssistantUsageSettings.isEnabled else { break }
            guard let meter = try? await container.meterRepository.meter(id: reading.meterID),
                  HomeAssistantSyncPolicy.mayStartRequest(enabled: true, meter: meter) else {
                continue
            }

            if let verified = try? await homeAssistantClient.sync(reading: reading, credentials: credentials) {
                var updated = reading
                updated.revision = max(updated.revision, verified.revision) + 1
                updated.status = .synced
                updated.lastSyncError = nil
                try? await repository.update(updated, expectedRevision: reading.revision)
                if let idx = readings.firstIndex(where: { $0.id == reading.id }) {
                    readings[idx] = updated
                }
                successCount += 1
            }
        }
        statusMessage = "\(successCount) leolvasás sikeresen szinkronizálva."
    }

    func registerAsTrainingExample(reading: MeterReading) async {
        guard let meter = try? await container.meterRepository.meter(id: reading.meterID),
              meter.recognition == .legacyGas8 else {
            errorMessage = "Csak automatikus felismerésű gázóra menthető tanítómintaként."
            return
        }

        guard let window = reading.window, let digits = reading.approvedDigits ?? reading.proposal?.digits else {
            errorMessage = "Csak kerettel és számértékkel rendelkező leolvasás menthető tanítómintaként."
            return
        }

        let formattedDigits = digits.contains(".") ? digits : formatDigitsWithDecimal(digits)
        let example = TrainingExample(
            readingID: reading.id,
            photoID: reading.photoID,
            window: window,
            digits: formattedDigits,
            decision: .approved,
            createdAt: .now
        )
        do {
            try await trainingExampleStore.record(example)
            trainingCount = (try? await trainingExampleStore.count()) ?? 0
            statusMessage = "Tanítóminta sikeresen elmentve a keretre és a számjegyekre!"
        } catch {
            errorMessage = "A tanítóminta mentése nem sikerült."
        }
    }

    private func formatDigitsWithDecimal(_ raw: String) -> String {
        guard raw.count == 8 else { return raw }
        let index = raw.index(raw.startIndex, offsetBy: 5)
        return String(raw[..<index]) + "." + String(raw[index...])
    }

    func photoURL(for photoID: UUID) -> URL? {
        try? archive.url(for: photoID)
    }
}
