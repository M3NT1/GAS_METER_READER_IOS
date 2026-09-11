import CoreGraphics
import ImageIO
import XCTest
@testable import GasPhotoIOS

final class PhotoArchiveTests: XCTestCase {
    func testStoreOriginalPreservesExactBytesAndCaptureTime() throws {
        let data = try jpegData()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try LocalPhotoArchive(rootDirectory: directory)

        let photo = try archive.storeOriginal(data, suggestedExtension: "jpg")

        XCTAssertEqual(try Data(contentsOf: archive.url(for: photo)), data)
        XCTAssertEqual(photo.capturedAt.timeIntervalSince1970, 1_781_815_422.865, accuracy: 0.001)
        XCTAssertTrue(photo.fileName.hasPrefix("originals/"))
        XCTAssertTrue(photo.fileName.hasSuffix(".jpg"))
    }

    private func jpegData() throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil),
              let context = CGContext(
                  data: nil,
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:06:18 22:43:42",
                "OffsetTimeOriginal": "+02:00",
                "SubSecTimeOriginal": "865"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
