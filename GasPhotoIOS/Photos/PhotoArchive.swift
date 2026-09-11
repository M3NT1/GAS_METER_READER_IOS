import CryptoKit
import Foundation

struct PhotoReference: Codable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let sha256: String
    let capturedAt: Date
}

protocol PhotoArchive: Sendable {
    func storeOriginal(_ data: Data, suggestedExtension: String) throws -> PhotoReference
    func url(for photo: PhotoReference) throws -> URL
}

enum PhotoArchiveError: Error, Equatable {
    case invalidExtension
    case invalidReference
    case contentHashCollision
}

final class LocalPhotoArchive: PhotoArchive, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager

    convenience init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("GasPhotoIOS", isDirectory: true)
        do {
            try self.init(rootDirectory: applicationSupport)
        } catch {
            fatalError("A helyi fotóarchívum nem indítható el.")
        }
    }

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
    }

    func storeOriginal(_ data: Data, suggestedExtension: String) throws -> PhotoReference {
        let metadata = try ImageMetadataReader.read(data: data)
        let fileExtension = try validatedExtension(suggestedExtension)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = "originals/\(digest).\(fileExtension)"
        let destination = try secureURL(forRelativePath: fileName)

        if fileManager.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else {
                throw PhotoArchiveError.contentHashCollision
            }
        } else {
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
        }

        return PhotoReference(
            id: UUID(),
            fileName: fileName,
            sha256: digest,
            capturedAt: metadata.capturedAt
        )
    }

    func url(for photo: PhotoReference) throws -> URL {
        try secureURL(forRelativePath: photo.fileName)
    }

    private var originalsDirectory: URL {
        rootDirectory.appendingPathComponent("originals", isDirectory: true)
    }

    private func validatedExtension(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isLetter || $0.isNumber }),
              normalized.count <= 10 else {
            throw PhotoArchiveError.invalidExtension
        }
        return normalized
    }

    private func secureURL(forRelativePath path: String) throws -> URL {
        let candidate = rootDirectory.appendingPathComponent(path).standardizedFileURL
        let allowedPrefix = rootDirectory.path.hasSuffix("/") ? rootDirectory.path : rootDirectory.path + "/"
        guard candidate.path.hasPrefix(allowedPrefix) else {
            throw PhotoArchiveError.invalidReference
        }
        return candidate
    }
}
