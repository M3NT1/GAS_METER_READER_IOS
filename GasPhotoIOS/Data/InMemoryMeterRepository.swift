import Foundation

@MainActor
protocol MeterRepository: AnyObject {
    func allMeters() async throws -> [Meter]
    func meter(id: String) async throws -> Meter
    func save(_ meter: Meter) async throws
}

enum MeterRepositoryError: LocalizedError, Equatable {
    case meterNotFound

    var errorDescription: String? {
        switch self {
        case .meterNotFound:
            "A mérő nem található a helyi adatbázisban."
        }
    }
}

@MainActor
final class InMemoryMeterRepository: MeterRepository {
    private var meters: [String: Meter] = [:]

    func allMeters() async throws -> [Meter] {
        meters.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func meter(id: String) async throws -> Meter {
        guard let meter = meters[id] else {
            throw MeterRepositoryError.meterNotFound
        }
        return meter
    }

    func save(_ meter: Meter) async throws {
        meters[meter.id] = meter
    }
}
