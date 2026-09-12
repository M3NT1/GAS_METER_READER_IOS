import Foundation

@MainActor
final class InMemoryReadingRepository: ReadingRepository {
    private var readings: [UUID: MeterReading] = [:]

    func insert(_ reading: MeterReading) async throws {
        guard readings[reading.id] == nil else {
            throw ReadingRepositoryError.duplicateReading
        }
        readings[reading.id] = reading
    }

    func reading(id: UUID) async throws -> MeterReading {
        guard let reading = readings[id] else {
            throw ReadingRepositoryError.readingNotFound
        }
        return reading
    }

    func update(_ reading: MeterReading, expectedRevision: Int) async throws {
        guard let stored = readings[reading.id] else {
            throw ReadingRepositoryError.readingNotFound
        }
        guard stored.revision == expectedRevision else {
            throw ReadingRepositoryError.staleRevision
        }
        var updated = reading
        updated.revision = expectedRevision + 1
        readings[reading.id] = updated
    }

    func pendingSync() async throws -> [MeterReading] {
        readings.values.filter { $0.status == .pendingSync }
    }

    func allReadings() async throws -> [MeterReading] {
        readings.values.sorted { $0.capturedAt > $1.capturedAt }
    }

    func delete(id: UUID) async throws {
        readings.removeValue(forKey: id)
    }
}
