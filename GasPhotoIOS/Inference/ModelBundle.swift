import Foundation

struct InferenceModelPaths: Sendable {
    let detector: URL
    let digitClassifier: URL
}

enum ModelBundleError: Error, Equatable {
    case missingDetector
    case missingDigitClassifier
}

final class ModelBundle {
    static func inferenceModelPaths(bundle: Bundle = Bundle(for: ModelBundle.self)) throws -> InferenceModelPaths {
        guard let detector = bundle.url(forResource: "window-detector-best", withExtension: "onnx") else {
            throw ModelBundleError.missingDetector
        }
        guard let digitClassifier = bundle.url(forResource: "digit-classifier-active", withExtension: "onnx") else {
            throw ModelBundleError.missingDigitClassifier
        }
        return InferenceModelPaths(detector: detector, digitClassifier: digitClassifier)
    }
}
