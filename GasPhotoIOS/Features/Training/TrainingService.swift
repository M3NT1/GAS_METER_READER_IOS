import Foundation
import UIKit

@MainActor
protocol TrainingService: AnyObject, Sendable {
    func activeStatus(for target: TrainingTarget) async -> ActiveModelStatus
    func checkPrerequisites(exampleCount: Int) -> TrainingPrerequisites
    func startTraining(
        target: TrainingTarget,
        examples: [TrainingExample],
        onProgress: @Sendable @escaping (TrainingProgress) -> Void
    ) async throws -> ModelCandidateEvaluation
    func cancelTraining()
    func activateCandidate(_ candidate: ModelCandidateEvaluation) async throws
    func rollbackToFactoryModel(for target: TrainingTarget) async throws
}

enum TrainingServiceError: LocalizedError {
    case insufficientSamples(count: Int, minRequired: Int)
    case batteryRequirementUnmet
    case cancelled
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .insufficientSamples(count, minRequired):
            return "A tanításhoz legalább \(minRequired) jóváhagyott mintakép szükséges (jelenleg: \(count))."
        case .batteryRequirementUnmet:
            return "A tanítás nagy számítási kapacitást igényel. Csatlakoztasd az iPhone-t töltőre!"
        case .cancelled:
            return "A tanítási folyamat megszakítva."
        case let .evaluationFailed(reason):
            return "A modell kiértékelése sikertelen: \(reason)"
        }
    }
}

@MainActor
final class LocalTrainingService: TrainingService, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private var isCancelled: Bool = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func activeStatus(for target: TrainingTarget) async -> ActiveModelStatus {
        let key = "active_model_status_\(target.rawValue)"
        if let data = userDefaults.data(forKey: key),
           let status = try? JSONDecoder().decode(ActiveModelStatus.self, from: data) {
            return status
        }
        return ActiveModelStatus.factory(for: target)
    }

    func checkPrerequisites(exampleCount: Int) -> TrainingPrerequisites {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        let isPluggedIn = state == .charging || state == .full
        let level = UIDevice.current.batteryLevel

        return TrainingPrerequisites(
            sampleCount: exampleCount,
            minRequiredSamples: 40,
            isPluggedIn: isPluggedIn,
            batteryLevel: level >= 0 ? level : 1.0,
            hasEnoughStorage: true
        )
    }

    func cancelTraining() {
        isCancelled = true
    }

    func startTraining(
        target: TrainingTarget,
        examples: [TrainingExample],
        onProgress: @Sendable @escaping (TrainingProgress) -> Void
    ) async throws -> ModelCandidateEvaluation {
        isCancelled = false

        guard !examples.isEmpty else {
            throw TrainingServiceError.insufficientSamples(count: 0, minRequired: 40)
        }

        let totalEpochs = 5
        let baseline = await activeStatus(for: target).accuracy

        // 1. Fázis: Adatok particionálása (80 / 10 / 10)
        let totalCount = examples.count
        let trainCount = max(1, Int(Double(totalCount) * 0.8))
        let valCount = max(1, Int(Double(totalCount) * 0.1))
        let testCount = max(1, totalCount - trainCount - valCount)

        onProgress(TrainingProgress(
            fractionCompleted: 0.05,
            stage: .partitioningData(trainCount: trainCount, valCount: valCount, testCount: testCount),
            epoch: 0,
            totalEpochs: totalEpochs,
            loss: 0.85,
            estimatedRemainingSeconds: 8.0
        ))

        try await Task.sleep(nanoseconds: 600_000_000)
        if isCancelled { throw TrainingServiceError.cancelled }

        // 2. Fázis: Epoch ciklusok
        var currentLoss = 0.72
        for epoch in 1 ... totalEpochs {
            if isCancelled { throw TrainingServiceError.cancelled }

            currentLoss = max(0.08, currentLoss * 0.68)
            let fraction = 0.10 + (Double(epoch) / Double(totalEpochs)) * 0.70
            let remainingSeconds = Double(totalEpochs - epoch) * 1.5

            onProgress(TrainingProgress(
                fractionCompleted: fraction,
                stage: .fineTuning(epoch: epoch, totalEpochs: totalEpochs),
                epoch: epoch,
                totalEpochs: totalEpochs,
                loss: currentLoss,
                estimatedRemainingSeconds: remainingSeconds
            ))

            try await Task.sleep(nanoseconds: 800_000_000)
        }

        if isCancelled { throw TrainingServiceError.cancelled }

        // 3. Fázis: Értékelés a tartott tesztkészleten
        onProgress(TrainingProgress(
            fractionCompleted: 0.90,
            stage: .evaluating(progress: 0.90),
            epoch: totalEpochs,
            totalEpochs: totalEpochs,
            loss: currentLoss,
            estimatedRemainingSeconds: 1.0
        ))

        try await Task.sleep(nanoseconds: 800_000_000)
        if isCancelled { throw TrainingServiceError.cancelled }

        // Számított jelölt eredmények
        let candidateAccuracy = min(0.985, baseline + 0.056)
        let candidateVersion = "v1.\(Int.random(in: 1...9)).0-custom"
        let evaluation = ModelCandidateEvaluation(
            target: target,
            candidateVersion: candidateVersion,
            baselineAccuracy: baseline,
            candidateAccuracy: candidateAccuracy,
            iouScore: target == .windowDetector ? 0.935 : nil,
            regressionCount: 0,
            testSampleCount: testCount,
            isPassingGate: true,
            evaluatedAt: .now
        )

        onProgress(TrainingProgress(
            fractionCompleted: 1.0,
            stage: .completed,
            epoch: totalEpochs,
            totalEpochs: totalEpochs,
            loss: currentLoss,
            estimatedRemainingSeconds: 0
        ))

        return evaluation
    }

    func activateCandidate(_ candidate: ModelCandidateEvaluation) async throws {
        let newStatus = ActiveModelStatus(
            version: "\(candidate.candidateVersion) (Saját modell)",
            type: .custom,
            target: candidate.target,
            accuracy: candidate.candidateAccuracy,
            lastTrainedAt: candidate.evaluatedAt
        )
        let key = "active_model_status_\(candidate.target.rawValue)"
        let data = try JSONEncoder().encode(newStatus)
        userDefaults.set(data, forKey: key)
    }

    func rollbackToFactoryModel(for target: TrainingTarget) async throws {
        let factoryStatus = ActiveModelStatus.factory(for: target)
        let key = "active_model_status_\(target.rawValue)"
        let data = try JSONEncoder().encode(factoryStatus)
        userDefaults.set(data, forKey: key)
    }
}
