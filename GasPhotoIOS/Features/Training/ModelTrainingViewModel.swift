import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ModelTrainingViewModel {
    let trainingExampleStore: any TrainingExampleStore
    let trainingService: any TrainingService

    var selectedTarget: TrainingTarget = .digitClassifier {
        didSet {
            Task { await loadActiveStatus() }
        }
    }

    var activeStatus: ActiveModelStatus? = nil
    var prerequisites: TrainingPrerequisites? = nil
    var progress: TrainingProgress? = nil
    var candidateEvaluation: ModelCandidateEvaluation? = nil
    var isTraining: Bool = false
    var statusMessage: String? = nil
    var errorMessage: String? = nil
    var showRollbackConfirm: Bool = false

    init(
        trainingExampleStore: any TrainingExampleStore,
        trainingService: any TrainingService
    ) {
        self.trainingExampleStore = trainingExampleStore
        self.trainingService = trainingService
    }

    func load() async {
        await loadActiveStatus()
        await checkPrerequisites()
    }

    func loadActiveStatus() async {
        activeStatus = await trainingService.activeStatus(for: selectedTarget)
    }

    func checkPrerequisites() async {
        let count = (try? await trainingExampleStore.count()) ?? 0
        prerequisites = trainingService.checkPrerequisites(exampleCount: count)
    }

    func startTraining(allowSampleOverride: Bool = false) async {
        errorMessage = nil
        statusMessage = nil
        candidateEvaluation = nil

        await checkPrerequisites()
        guard let prereq = prerequisites else { return }

        if !prereq.hasEnoughSamples && !allowSampleOverride {
            errorMessage = "A tanításhoz legalább \(prereq.minRequiredSamples) jóváhagyott mintakép szükséges."
            return
        }

        let examples = (try? await trainingExampleStore.allExamples()) ?? []
        guard !examples.isEmpty else {
            errorMessage = "Nem található mentett tanítóminta a készüléken."
            return
        }

        isTraining = true
        progress = TrainingProgress(
            fractionCompleted: 0.02,
            stage: .preparing,
            epoch: 0,
            totalEpochs: 5,
            loss: 0.85,
            estimatedRemainingSeconds: 10.0
        )

        do {
            let evaluation = try await trainingService.startTraining(
                target: selectedTarget,
                examples: examples,
                onProgress: { [weak self] prog in
                    Task { @MainActor in
                        self?.progress = prog
                    }
                }
            )
            candidateEvaluation = evaluation
            statusMessage = "A tanítás sikeresen befejeződött! Ellenőrizd a kiértékelést."
        } catch TrainingServiceError.cancelled {
            statusMessage = "A tanítás felhasználói kérésre leállítva."
        } catch {
            errorMessage = "Hiba a tanítás során: \(error.localizedDescription)"
        }

        isTraining = false
    }

    func cancelTraining() {
        trainingService.cancelTraining()
        isTraining = false
        progress = nil
    }

    func activateCandidate() async {
        guard let candidate = candidateEvaluation else { return }
        do {
            try await trainingService.activateCandidate(candidate)
            await loadActiveStatus()
            candidateEvaluation = nil
            progress = nil
            statusMessage = "Az új finomhangolt modell (\(candidate.candidateVersion)) mostantól aktív ezen az iPhone-on!"
        } catch {
            errorMessage = "A modell aktiválása sikertelen: \(error.localizedDescription)"
        }
    }

    func discardCandidate() {
        candidateEvaluation = nil
        progress = nil
        statusMessage = "A jelölt modell elvetve."
    }

    func rollbackToFactoryModel() async {
        do {
            try await trainingService.rollbackToFactoryModel(for: selectedTarget)
            await loadActiveStatus()
            statusMessage = "Visszaállítva a gyári alapértelmezett modellre."
        } catch {
            errorMessage = "Visszaállítás sikertelen: \(error.localizedDescription)"
        }
    }
}
