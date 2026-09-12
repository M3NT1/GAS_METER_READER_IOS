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
        XCTAssertEqual(photo.fileName, "originals/\(photo.id.uuidString).jpg")
    }

    func testStoreOriginalStoresByPhotoIDAndResolvesByURLForPhotoID() throws {
        let data = try jpegData()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try LocalPhotoArchive(rootDirectory: directory)

        let photo = try archive.storeOriginal(data, suggestedExtension: "jpg")
        let urlFromID = try archive.url(for: photo.id)

        XCTAssertEqual(urlFromID, try archive.url(for: photo))
        XCTAssertEqual(try Data(contentsOf: urlFromID), data)
    }

    func testStoreOriginalWithExplicitIDPreservesPhotoIdentifier() throws {
        let data = try jpegData()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try LocalPhotoArchive(rootDirectory: directory)
        let explicitID = UUID()

        let photo = try archive.storeOriginal(data, id: explicitID, suggestedExtension: "jpg")

        XCTAssertEqual(photo.id, explicitID)
        XCTAssertEqual(photo.fileName, "originals/\(explicitID.uuidString).jpg")
        XCTAssertEqual(try archive.url(for: explicitID), try archive.url(for: photo))
    }

    func testURLForUnknownPhotoIDThrowsPhotoNotFound() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try LocalPhotoArchive(rootDirectory: directory)

        XCTAssertThrowsError(try archive.url(for: UUID())) { error in
            XCTAssertEqual(error as? PhotoArchiveError, .photoNotFound)
        }
    }

    func testCollisionWhenDifferentDataStoredWithSameID() throws {
        let data = try jpegData()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try LocalPhotoArchive(rootDirectory: directory)
        let sharedID = UUID()

        _ = try archive.storeOriginal(data, id: sharedID, suggestedExtension: "jpg")

        var differentData = data
        differentData.append(Data([0x00, 0x01]))
        XCTAssertThrowsError(try archive.storeOriginal(differentData, id: sharedID, suggestedExtension: "jpg")) { error in
            XCTAssertEqual(error as? PhotoArchiveError, .contentHashCollision)
        }
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
                kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
                kCGImagePropertyExifSubsecTimeOriginal: "865"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
