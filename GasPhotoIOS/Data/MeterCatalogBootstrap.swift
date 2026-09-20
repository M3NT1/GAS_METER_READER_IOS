import Foundation

@MainActor
enum MeterCatalogBootstrap {
    static func run(readings: [MeterReading], meters: any MeterRepository) async throws {
        let existingIDs = Set(try await meters.allMeters().map(\.id))
        let readingIDs = Set(readings.map(\.meterID))

        for meterID in readingIDs.subtracting(existingIDs).sorted() {
            try await meters.save(legacyMeter(for: meterID))
        }
    }

    private static func legacyMeter(for id: String) -> Meter {
        if id == "gas_main" {
            return Meter(
                id: id,
                name: "Gázóra",
                kind: .gas,
                format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
                recognition: .legacyGas8,
                isArchived: false
            )
        }

        return Meter(
            id: id,
            name: "Korábbi mérő (\(id))",
            kind: .gas,
            format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
            recognition: .manual,
            isArchived: true
        )
    }
}
