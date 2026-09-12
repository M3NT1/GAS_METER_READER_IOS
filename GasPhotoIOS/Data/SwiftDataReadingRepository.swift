import Foundation
import SwiftData

@MainActor
protocol ReadingRepository: AnyObject {
    func insert(_ reading: MeterReading) async throws
    func reading(id: UUID) async throws -> MeterReading
    func update(_ reading: MeterReading, expectedRevision: Int) async throws
    func pendingSync() async throws -> [MeterReading]
    func allReadings() async throws -> [MeterReading]
    func delete(id: UUID) async throws
}

enum ReadingRepositoryError: LocalizedError, Equatable {
    case duplicateReading
    case readingNotFound
    case staleRevision

    var errorDescription: String? {
        switch self {
        case .duplicateReading:
            return "Ez a leolvasás már szerepel az adatbázisban."
        case .readingNotFound:
            return "A leolvasás nem található a helyi adatbázisban."
        case .staleRevision:
            return "A leolvasás állapota időközben frissült a háttérben."
        }
    }
}

@Model
final class PersistedMeterReading {
    @Attribute(.unique) var id: UUID
    var revision: Int
    var meterID: String
    var photoID: UUID
    var capturedAt: Date
    var windowData: Data?
    var proposalData: Data?
    var approvedDigits: String?
    var statusRawValue: String
    var modelVersion: String?
    var lastSyncError: String?

    init(reading: MeterReading) throws {
        id = reading.id
        revision = reading.revision
        meterID = reading.meterID
        photoID = reading.photoID
        capturedAt = reading.capturedAt
        windowData = try Self.encode(reading.window)
        proposalData = try Self.encode(reading.proposal)
        approvedDigits = reading.approvedDigits
        statusRawValue = reading.status.rawValue
        modelVersion = reading.modelVersion
        lastSyncError = reading.lastSyncError
    }

    func replace(with reading: MeterReading, revision: Int) throws {
        self.revision = revision
        meterID = reading.meterID
        photoID = reading.photoID
        capturedAt = reading.capturedAt
        windowData = try Self.encode(reading.window)
        proposalData = try Self.encode(reading.proposal)
        approvedDigits = reading.approvedDigits
        statusRawValue = reading.status.rawValue
        modelVersion = reading.modelVersion
        lastSyncError = reading.lastSyncError
    }

    func domainValue() throws -> MeterReading {
        guard let status = ReadingStatus(rawValue: statusRawValue) else {
            throw ReadingRepositoryError.readingNotFound
        }

        return MeterReading(
            id: id,
            revision: revision,
            meterID: meterID,
            photoID: photoID,
            capturedAt: capturedAt,
            window: try Self.decode(windowData, as: NormalizedRect.self),
            proposal: try Self.decode(proposalData, as: DigitProposal.self),
            approvedDigits: approvedDigits,
            status: status,
            modelVersion: modelVersion,
            lastSyncError: lastSyncError
        )
    }

    private static func encode<Value: Encodable>(_ value: Value?) throws -> Data? {
        try value.map { try JSONEncoder().encode($0) }
    }

    private static func decode<Value: Decodable>(_ data: Data?, as type: Value.Type) throws -> Value? {
        try data.map { try JSONDecoder().decode(Value.self, from: $0) }
    }
}

@MainActor
final class SwiftDataReadingRepository: ReadingRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func insert(_ reading: MeterReading) async throws {
        guard try storedReading(id: reading.id) == nil else {
            throw ReadingRepositoryError.duplicateReading
        }
        modelContext.insert(try PersistedMeterReading(reading: reading))
        try modelContext.save()
    }

    func reading(id: UUID) async throws -> MeterReading {
        guard let stored = try storedReading(id: id) else {
            throw ReadingRepositoryError.readingNotFound
        }
        return try stored.domainValue()
    }

    func update(_ reading: MeterReading, expectedRevision: Int) async throws {
        guard let stored = try storedReading(id: reading.id) else {
            throw ReadingRepositoryError.readingNotFound
        }
        guard stored.revision == expectedRevision else {
            throw ReadingRepositoryError.staleRevision
        }
        try stored.replace(with: reading, revision: expectedRevision + 1)
        try modelContext.save()
    }

    func pendingSync() async throws -> [MeterReading] {
        let descriptor = FetchDescriptor<PersistedMeterReading>()
        return try modelContext.fetch(descriptor)
            .filter { $0.statusRawValue == ReadingStatus.pendingSync.rawValue }
            .map { try $0.domainValue() }
    }

    func allReadings() async throws -> [MeterReading] {
        let descriptor = FetchDescriptor<PersistedMeterReading>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { try? $0.domainValue() }
    }

    func delete(id: UUID) async throws {
        if let stored = try storedReading(id: id) {
            modelContext.delete(stored)
            try modelContext.save()
        }
    }

    private func storedReading(id: UUID) throws -> PersistedMeterReading? {
        let descriptor = FetchDescriptor<PersistedMeterReading>()
        return try modelContext.fetch(descriptor).first { $0.id == id }
    }
}
