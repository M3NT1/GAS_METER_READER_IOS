import Foundation
import SwiftData

@Model
final class PersistedMeter {
    @Attribute(.unique) var id: String
    var name: String
    var kindRawValue: String
    var integerDigits: Int
    var fractionalDigits: Int
    var recognitionRawValue: String
    var isArchived: Bool

    init(meter: Meter) {
        id = meter.id
        name = meter.name
        kindRawValue = meter.kind.rawValue
        integerDigits = meter.format.integerDigits
        fractionalDigits = meter.format.fractionalDigits
        recognitionRawValue = meter.recognition.rawValue
        isArchived = meter.isArchived
    }

    func replace(with meter: Meter) {
        name = meter.name
        kindRawValue = meter.kind.rawValue
        integerDigits = meter.format.integerDigits
        fractionalDigits = meter.format.fractionalDigits
        recognitionRawValue = meter.recognition.rawValue
        isArchived = meter.isArchived
    }

    func domainValue() throws -> Meter {
        guard let kind = MeterKind(rawValue: kindRawValue),
              let recognition = RecognitionProfile(rawValue: recognitionRawValue),
              let format = MeterFormat(validating: integerDigits, fractionalDigits: fractionalDigits) else {
            throw MeterRepositoryError.meterNotFound
        }
        return Meter(
            id: id,
            name: name,
            kind: kind,
            format: format,
            recognition: recognition,
            isArchived: isArchived
        )
    }
}

@MainActor
final class SwiftDataMeterRepository: MeterRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func allMeters() async throws -> [Meter] {
        let descriptor = FetchDescriptor<PersistedMeter>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor).compactMap { try? $0.domainValue() }
    }

    func meter(id: String) async throws -> Meter {
        guard let stored = try storedMeter(id: id) else {
            throw MeterRepositoryError.meterNotFound
        }
        return try stored.domainValue()
    }

    func save(_ meter: Meter) async throws {
        if let stored = try storedMeter(id: meter.id) {
            stored.replace(with: meter)
        } else {
            modelContext.insert(PersistedMeter(meter: meter))
        }
        try modelContext.save()
    }

    private func storedMeter(id: String) throws -> PersistedMeter? {
        try modelContext.fetch(FetchDescriptor<PersistedMeter>()).first { $0.id == id }
    }
}
