import Foundation
import ImageIO

struct PhotoCaptureMetadata: Equatable, Sendable {
    let capturedAt: Date
}

enum ImageMetadataError: Error, Equatable {
    case unreadableImage
    case missingCaptureTime
    case malformedCaptureTime
}

enum ImageMetadataReader {
    static func read(data: Data) throws -> PhotoCaptureMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              let offset = exif["OffsetTimeOriginal" as CFString] as? String else {
            throw ImageMetadataError.missingCaptureTime
        }

        let subsecond = exif["SubSecTimeOriginal" as CFString] as? String ?? "0"
        return PhotoCaptureMetadata(capturedAt: try captureDate(
            original: original,
            offset: offset,
            subsecond: subsecond
        ))
    }

    private static func captureDate(original: String, offset: String, subsecond: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let unadjustedDate = formatter.date(from: original),
              let offsetSeconds = seconds(in: offset),
              let fraction = fractionalSeconds(from: subsecond) else {
            throw ImageMetadataError.malformedCaptureTime
        }

        return unadjustedDate.addingTimeInterval(TimeInterval(-offsetSeconds) + fraction)
    }

    private static func seconds(in offset: String) -> Int? {
        guard offset.count == 6,
              let sign = offset.first,
              sign == "+" || sign == "-",
              offset[offset.index(offset.startIndex, offsetBy: 3)] == ":",
              let hours = Int(offset.dropFirst().prefix(2)),
              let minutes = Int(offset.suffix(2)),
              hours <= 23,
              minutes <= 59 else {
            return nil
        }

        let value = (hours * 60 + minutes) * 60
        return sign == "+" ? value : -value
    }

    private static func fractionalSeconds(from value: String) -> Double? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { return nil }
        return Double("0.\(value)")
    }
}
