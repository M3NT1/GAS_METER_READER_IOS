import Foundation

struct DetectorCandidate: Equatable, Sendable {
    let window: NormalizedRect
    let confidence: Double
}

struct ClassifierOutput: Equatable, Sendable {
    let digit: Int
    let confidence: Double
}

struct RecognitionResult: Equatable, Sendable {
    let window: NormalizedRect?
    let proposal: DigitProposal?
    let decimalReviewPositions: [Int]
}

enum InferenceProgress: Sendable, Equatable {
    case detectingWindow
    case classifyingDigits(window: NormalizedRect?)
}

enum InferenceError: Error, Equatable {
    case invalidClassifierOutput
}

protocol InferenceRuntime: Sendable {
    func detectorCandidates(imageURL: URL) async throws -> [DetectorCandidate]
    func classifyRollers(imageURL: URL, window: NormalizedRect) async throws -> [ClassifierOutput]
}

final class InferenceService: @unchecked Sendable {
    private let runtime: any InferenceRuntime

    init(runtime: any InferenceRuntime) {
        self.runtime = runtime
    }

    func propose(
        imageURL: URL,
        manualWindow: NormalizedRect?,
        onProgress: (@Sendable (InferenceProgress) -> Void)? = nil
    ) async throws -> RecognitionResult {
        let window: NormalizedRect?
        if let manualWindow {
            window = manualWindow
        } else {
            onProgress?(.detectingWindow)
            let accepted = try await runtime.detectorCandidates(imageURL: imageURL)
                .filter { $0.confidence >= 0.55 }
            window = accepted.count == 1 ? accepted[0].window : nil
        }

        onProgress?(.classifyingDigits(window: window))
        guard let window else {
            return RecognitionResult(window: nil, proposal: nil, decimalReviewPositions: [])
        }

        let outputs = try await runtime.classifyRollers(imageURL: imageURL, window: window)
        guard outputs.count == 8, outputs.allSatisfy({ (0...9).contains($0.digit) }) else {
            throw InferenceError.invalidClassifierOutput
        }

        let digits = outputs.map { String($0.digit) }.joined()
        let confidences = outputs.map(\.confidence)
        let uncertainPositions = outputs.indices.filter { index in
            confidences[index] < (index < 5 ? 0.75 : 0.50)
        }
        let decimalReviewPositions = outputs.indices.filter { index in
            index >= 5 && confidences[index] >= 0.50 && confidences[index] < 0.75
        }
        return RecognitionResult(
            window: window,
            proposal: DigitProposal(
                digits: digits,
                confidences: confidences,
                uncertainPositions: uncertainPositions
            ),
            decimalReviewPositions: decimalReviewPositions
        )
    }
}
