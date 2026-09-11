import CoreGraphics
import XCTest
@testable import GasPhotoIOS

final class ImagePreprocessorTests: XCTestCase {
    func testDetectorPreprocessProduces960SquareTensor() throws {
        let image = try fixtureImage(width: 2, height: 1)

        let tensor = try ImagePreprocessor.detectorTensor(from: image)

        XCTAssertEqual(tensor.shape, [1, 3, 960, 960])
        XCTAssertEqual(tensor.values.count, 1 * 3 * 960 * 960)
    }

    func testSplitsTightWindowIntoEightOrderedRollers() throws {
        let rects = try ImagePreprocessor.rollerRects(in: CGSize(width: 800, height: 100))

        XCTAssertEqual(rects.count, 8)
        XCTAssertEqual(rects.first, CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rects.last, CGRect(x: 700, y: 0, width: 100, height: 100))
    }

    private func fixtureImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
}
