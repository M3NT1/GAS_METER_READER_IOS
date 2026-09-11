import CoreGraphics
import Foundation
import ImageIO

enum ONNXRuntimeError: Error, Equatable {
    case unreadableImage
    case invalidTensor
    case invalidDetectorOutput
    case invalidClassifierOutput
    case invalidWindow
}

actor ONNXRuntime: InferenceRuntime {
    private let bridge: ORTInferenceBridge

    init(paths: InferenceModelPaths) throws {
        bridge = try ORTInferenceBridge(
            detectorModelPath: paths.detector.path,
            digitModelPath: paths.digitClassifier.path
        )
    }

    func detectorCandidates(imageURL: URL) async throws -> [DetectorCandidate] {
        let image = try cgImage(at: imageURL)
        let tensor = try ImagePreprocessor.detectorTensor(from: image)
        let output = try bridge.detectorOutput(forInput: tensorData(tensor))
        return try decodeDetectorOutput(output, imageSize: CGSize(width: image.width, height: image.height))
    }

    func classifyRollers(imageURL: URL, window: NormalizedRect) async throws -> [ClassifierOutput] {
        let image = try cgImage(at: imageURL)
        let crop = try crop(image: image, to: window)
        return try ImagePreprocessor.rollerRects(in: CGSize(width: crop.width, height: crop.height)).map { rect in
            guard let roller = crop.cropping(to: rect.integral) else {
                throw ONNXRuntimeError.invalidWindow
            }
            let tensor = try ImagePreprocessor.classifierTensor(from: roller)
            let output = try bridge.digitOutput(forInput: tensorData(tensor))
            return try decodeClassifierOutput(output)
        }
    }

    private func cgImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ONNXRuntimeError.unreadableImage
        }
        return image
    }

    private func tensorData(_ tensor: FloatTensor) -> Data {
        tensor.values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func decodeDetectorOutput(_ data: Data, imageSize: CGSize) throws -> [DetectorCandidate] {
        let values = floats(in: data)
        let boxCount = 18_900
        guard values.count == boxCount * 5 else {
            throw ONNXRuntimeError.invalidDetectorOutput
        }

        let scale = min(960 / imageSize.width, 960 / imageSize.height)
        let paddingX = (960 - imageSize.width * scale) / 2
        let paddingY = (960 - imageSize.height * scale) / 2
        let candidates = (0..<boxCount).compactMap { index -> DetectorCandidate? in
            let confidence = Double(values[boxCount * 4 + index])
            guard confidence >= 0.55 else { return nil }
            let centerX = CGFloat(values[index])
            let centerY = CGFloat(values[boxCount + index])
            let width = CGFloat(values[boxCount * 2 + index])
            let height = CGFloat(values[boxCount * 3 + index])
            let left = ((centerX - width / 2) - paddingX) / (imageSize.width * scale)
            let top = ((centerY - height / 2) - paddingY) / (imageSize.height * scale)
            let right = ((centerX + width / 2) - paddingX) / (imageSize.width * scale)
            let bottom = ((centerY + height / 2) - paddingY) / (imageSize.height * scale)
            let rect = NormalizedRect(
                left: max(0, Double(left)),
                top: max(0, Double(top)),
                right: min(1, Double(right)),
                bottom: min(1, Double(bottom))
            )
            guard rect.left < rect.right, rect.top < rect.bottom else { return nil }
            return DetectorCandidate(window: rect, confidence: confidence)
        }.sorted { $0.confidence > $1.confidence }

        return nonMaximumSuppressed(candidates)
    }

    private func decodeClassifierOutput(_ data: Data) throws -> ClassifierOutput {
        let values = floats(in: data)
        guard values.count == 10 else {
            throw ONNXRuntimeError.invalidClassifierOutput
        }
        let probabilities: [Float]
        let sum = values.reduce(0, +)
        if values.allSatisfy({ $0 >= 0 }) && abs(sum - 1) < 0.001 {
            probabilities = values
        } else {
            let maximum = values.max() ?? 0
            let exponentials = values.map { exp($0 - maximum) }
            let normalizer = exponentials.reduce(0, +)
            probabilities = exponentials.map { $0 / normalizer }
        }
        guard let maximum = probabilities.enumerated().max(by: { $0.element < $1.element }) else {
            throw ONNXRuntimeError.invalidClassifierOutput
        }
        return ClassifierOutput(digit: maximum.offset, confidence: Double(maximum.element))
    }

    private func crop(image: CGImage, to window: NormalizedRect) throws -> CGImage {
        guard window.left >= 0, window.top >= 0, window.right <= 1, window.bottom <= 1,
              window.left < window.right, window.top < window.bottom else {
            throw ONNXRuntimeError.invalidWindow
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let left = CGFloat(window.left) * width
        let top = CGFloat(window.top) * height
        let right = CGFloat(window.right) * width
        let bottom = CGFloat(window.bottom) * height
        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top).integral
        guard let cropped = image.cropping(to: rect) else {
            throw ONNXRuntimeError.invalidWindow
        }
        return cropped
    }

    private func floats(in data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func nonMaximumSuppressed(_ candidates: [DetectorCandidate]) -> [DetectorCandidate] {
        candidates.reduce(into: [DetectorCandidate]()) { kept, candidate in
            if kept.allSatisfy({ intersectionOverUnion($0.window, candidate.window) < 0.5 }) {
                kept.append(candidate)
            }
        }
    }

    private func intersectionOverUnion(_ first: NormalizedRect, _ second: NormalizedRect) -> Double {
        let left = max(first.left, second.left)
        let top = max(first.top, second.top)
        let right = min(first.right, second.right)
        let bottom = min(first.bottom, second.bottom)
        let intersection = max(0, right - left) * max(0, bottom - top)
        let union = (first.right - first.left) * (first.bottom - first.top)
            + (second.right - second.left) * (second.bottom - second.top)
            - intersection
        return union > 0 ? intersection / union : 0
    }
}
