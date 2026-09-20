import XCTest
import CoreGraphics
import ImageIO
@testable import GasPhotoIOS

final class ONNXRuntimeTests: XCTestCase {
    func testBridgeLoadsBothBundledInferenceModels() throws {
        let paths = try ModelBundle.inferenceModelPaths(bundle: Bundle(for: ModelBundle.self))

        XCTAssertNoThrow(
            try ORTInferenceBridge(
                detectorModelPath: paths.detector.path,
                digitModelPath: paths.digitClassifier.path
            )
        )
    }

    func testRuntimeClassifiesEightRollersFromManualWindow() async throws {
        let imageURL = try blankJPEG()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let paths = try ModelBundle.inferenceModelPaths(bundle: Bundle(for: ModelBundle.self))
        let runtime = try ONNXRuntime(paths: paths)
        let window = NormalizedRect(left: 0, top: 0, right: 1, bottom: 1)

        let outputs = try await runtime.classifyRollers(imageURL: imageURL, window: window)

        XCTAssertEqual(outputs.count, 8)
        XCTAssertTrue(outputs.allSatisfy { (0...9).contains($0.digit) })
        XCTAssertTrue(outputs.allSatisfy { (0...1).contains($0.confidence) })
    }

    func testRuntimeHandlesExifOrientationSixImage() async throws {
        let imageURL = try blankJPEGWithExifOrientation(orientation: 6)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let paths = try ModelBundle.inferenceModelPaths(bundle: Bundle(for: ModelBundle.self))
        let runtime = try ONNXRuntime(paths: paths)
        let window = NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4)

        let outputs = try await runtime.classifyRollers(imageURL: imageURL, window: window)

        XCTAssertEqual(outputs.count, 8)
        XCTAssertTrue(outputs.allSatisfy { (0...9).contains($0.digit) })
    }

    func testDetectorAndClassifierOnRealPhotoIfAvailable() async throws {
        let candidatePath = "/Users/kasnyiklaszlo/_DEV/_GAZORA_DIGITALIZALAS/data/originals/550a97d07d37f9d12a7ea22f723b369ba7e5682f8353315844dce5f53f6f62b1.heic"
        guard FileManager.default.fileExists(atPath: candidatePath) else { return }
        let imageURL = URL(fileURLWithPath: candidatePath)
        let paths = try ModelBundle.inferenceModelPaths(bundle: Bundle(for: ModelBundle.self))
        let runtime = try ONNXRuntime(paths: paths)

        let candidates = try await runtime.detectorCandidates(imageURL: imageURL)
        XCTAssertEqual(candidates.count, 1)
        guard let bestCandidate = candidates.first else { return }
        XCTAssertGreaterThan(bestCandidate.confidence, 0.70)

        let outputs = try await runtime.classifyRollers(imageURL: imageURL, window: bestCandidate.window)
        XCTAssertEqual(outputs.count, 8)
        let digits = outputs.map { String($0.digit) }.joined()
        XCTAssertEqual(digits, "01879767")
        XCTAssertTrue(outputs.allSatisfy { $0.confidence > 0.90 })
    }

    private func blankJPEG() throws -> URL {
        try blankJPEGWithExifOrientation(orientation: 1)
    }

    private func blankJPEGWithExifOrientation(orientation: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil),
              let context = CGContext(
                  data: nil,
                  width: 800,
                  height: 600,
                  bitsPerComponent: 8,
                  bytesPerRow: 800 * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
