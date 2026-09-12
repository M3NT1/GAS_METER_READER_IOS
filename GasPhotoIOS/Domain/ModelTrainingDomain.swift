import Foundation

enum TrainingTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case digitClassifier = "digit_classifier"
    case windowDetector = "window_detector"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digitClassifier:
            return "Számjegyosztályozó (Görgők)"
        case .windowDetector:
            return "Számlálókeret-detektor"
        }
    }

    var subtitle: String {
        switch self {
        case .digitClassifier:
            return "A fekete és piros számlálógörgők felismerési pontosságát növeli"
        case .windowDetector:
            return "A mérőóra számlálóablakának automatikus felismerését és illesztését javítja"
        }
    }

    var icon: String {
        switch self {
        case .digitClassifier:
            return "number.square.fill"
        case .windowDetector:
            return "viewfinder.rectangular"
        }
    }
}

enum TrainingStage: Equatable, Sendable {
    case preparing
    case partitioningData(trainCount: Int, valCount: Int, testCount: Int)
    case fineTuning(epoch: Int, totalEpochs: Int)
    case evaluating(progress: Double)
    case completed

    var displayName: String {
        switch self {
        case .preparing:
            return "Előkészítés & adatok ellenőrzése..."
        case let .partitioningData(train, val, test):
            return "Adathalmaz particionálása: \(train) tanító / \(val) validációs / \(test) teszt"
        case let .fineTuning(epoch, total):
            return "ONNX Runtime finomhangolás: \(epoch). / \(total) ciklus"
        case .evaluating:
            return "Jelölt modell kiértékelése a tesztképeken..."
        case .completed:
            return "A tanítás sikeresen befejeződött!"
        }
    }
}

struct TrainingProgress: Equatable, Sendable {
    let fractionCompleted: Double
    let stage: TrainingStage
    let epoch: Int
    let totalEpochs: Int
    let loss: Double
    let estimatedRemainingSeconds: TimeInterval?

    init(
        fractionCompleted: Double,
        stage: TrainingStage,
        epoch: Int,
        totalEpochs: Int,
        loss: Double,
        estimatedRemainingSeconds: TimeInterval?
    ) {
        self.fractionCompleted = fractionCompleted
        self.stage = stage
        self.epoch = epoch
        self.totalEpochs = totalEpochs
        self.loss = loss
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
    }

    var formattedRemainingTime: String {
        guard let seconds = estimatedRemainingSeconds, seconds > 0 else {
            return "Számítás..."
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "kb. \(mins) p \(secs) mp"
        } else {
            return "kb. \(secs) mp"
        }
    }
}

struct ModelCandidateEvaluation: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let target: TrainingTarget
    let candidateVersion: String
    let baselineAccuracy: Double
    let candidateAccuracy: Double
    let iouScore: Double?
    let regressionCount: Int
    let testSampleCount: Int
    let isPassingGate: Bool
    let evaluatedAt: Date

    init(
        id: UUID = UUID(),
        target: TrainingTarget,
        candidateVersion: String,
        baselineAccuracy: Double,
        candidateAccuracy: Double,
        iouScore: Double? = nil,
        regressionCount: Int = 0,
        testSampleCount: Int,
        isPassingGate: Bool,
        evaluatedAt: Date = .now
    ) {
        self.id = id
        self.target = target
        self.candidateVersion = candidateVersion
        self.baselineAccuracy = baselineAccuracy
        self.candidateAccuracy = candidateAccuracy
        self.iouScore = iouScore
        self.regressionCount = regressionCount
        self.testSampleCount = testSampleCount
        self.isPassingGate = isPassingGate
        self.evaluatedAt = evaluatedAt
    }

    var accuracyImprovementPercent: Double {
        (candidateAccuracy - baselineAccuracy) * 100.0
    }
}

enum ModelType: String, Codable, Sendable {
    case factory = "factory"
    case custom = "custom"
}

struct ActiveModelStatus: Equatable, Codable, Sendable {
    let version: String
    let type: ModelType
    let target: TrainingTarget
    let accuracy: Double
    let lastTrainedAt: Date?

    init(
        version: String,
        type: ModelType,
        target: TrainingTarget,
        accuracy: Double,
        lastTrainedAt: Date? = nil
    ) {
        self.version = version
        self.type = type
        self.target = target
        self.accuracy = accuracy
        self.lastTrainedAt = lastTrainedAt
    }

    static func factory(for target: TrainingTarget) -> ActiveModelStatus {
        ActiveModelStatus(
            version: "v1.0.0 (Gyári)",
            type: .factory,
            target: target,
            accuracy: target == .digitClassifier ? 0.892 : 0.865,
            lastTrainedAt: nil
        )
    }
}

struct TrainingPrerequisites: Equatable, Sendable {
    let sampleCount: Int
    let minRequiredSamples: Int
    let isPluggedIn: Bool
    let batteryLevel: Float
    let hasEnoughStorage: Bool

    init(
        sampleCount: Int,
        minRequiredSamples: Int = 40,
        isPluggedIn: Bool,
        batteryLevel: Float,
        hasEnoughStorage: Bool = true
    ) {
        self.sampleCount = sampleCount
        self.minRequiredSamples = minRequiredSamples
        self.isPluggedIn = isPluggedIn
        self.batteryLevel = batteryLevel
        self.hasEnoughStorage = hasEnoughStorage
    }

    var hasEnoughSamples: Bool { sampleCount >= minRequiredSamples }
    var isBatteryOk: Bool { isPluggedIn || batteryLevel >= 0.50 }
    var isReadyToTrain: Bool { hasEnoughSamples && isBatteryOk && hasEnoughStorage }

    var unmetReasons: [String] {
        var reasons: [String] = []
        if !hasEnoughSamples {
            reasons.append("Még \(minRequiredSamples - sampleCount) db jóváhagyott mintakép szükséges (jelenleg: \(sampleCount)/\(minRequiredSamples)).")
        }
        if !isBatteryOk {
            reasons.append("Csatlakoztasd az iPhone-t töltőre a nagy számítási igényű modelltanításhoz!")
        }
        if !hasEnoughStorage {
            reasons.append("Legalább 200 MB szabad tárhely szükséges a készüléken.")
        }
        return reasons
    }
}
