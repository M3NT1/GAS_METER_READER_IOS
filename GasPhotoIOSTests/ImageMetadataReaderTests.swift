import CoreGraphics
import ImageIO
import XCTest
@testable import GasPhotoIOS

final class ImageMetadataReaderTests: XCTestCase {
    func testReadsOriginalSubsecondCaptureTimeWithOffset() throws {
        let data = try jpegData(
            dateTimeOriginal: "2026:06:18 22:43:42",
            offsetTimeOriginal: "+02:00",
            subsecondTimeOriginal: "865"
        )

        let metadata = try ImageMetadataReader.read(data: data)

        XCTAssertEqual(metadata.capturedAt.timeIntervalSince1970, 1_781_815_422.865, accuracy: 0.001)
    }

    private func jpegData(
        dateTimeOriginal: String,
        offsetTimeOriginal: String,
        subsecondTimeOriginal: String
    ) throws -> Data {
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
                kCGImagePropertyExifDateTimeOriginal: dateTimeOriginal,
                kCGImagePropertyExifOffsetTimeOriginal: offsetTimeOriginal,
                kCGImagePropertyExifSubsecTimeOriginal: subsecondTimeOriginal
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
