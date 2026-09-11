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

    private func blankJPEG() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil),
              let context = CGContext(
                  data: nil,
                  width: 800,
                  height: 100,
                  bitsPerComponent: 8,
                  bytesPerRow: 800 * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
