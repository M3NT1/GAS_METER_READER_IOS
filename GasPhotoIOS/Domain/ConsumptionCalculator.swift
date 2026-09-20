import Foundation

struct ConsumptionInterval: Equatable, Sendable, Identifiable {
    var id: String { "\(fromReadingID.uuidString)-\(toReadingID.uuidString)" }
    let fromReadingID: UUID
    let toReadingID: UUID
    let start: Date
    let end: Date
    let amount: Decimal
    let fromValue: Decimal
    let toValue: Decimal
}

enum ConsumptionCalculationError: LocalizedError, Equatable {
    case decreasingValue(from: Decimal, to: Decimal, at: Date)
    case conflictingTimestamp(Date)
    case invalidReadingValue(String)

    var errorDescription: String? {
        switch self {
        case let .decreasingValue(from, to, date):
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            return "Csökkenő mérőállás található (\(from) -> \(to)) a következő időpontban: \(formatted)."
        case let .conflictingTimestamp(date):
            let formatted = date.formatted(date: .abbreviated, time: .standard)
            return "Ütköző vagy azonos leolvasási időpont található: \(formatted)."
        case let .invalidReadingValue(val):
            return "Érvénytelen leolvasási érték: \(val)"
        }
    }
}

enum ConsumptionCalculator {
    static func intervals(readings: [MeterReading], meter: Meter) throws -> [ConsumptionInterval] {
        let relevant = readings.filter { reading in
            reading.meterID == meter.id &&
            (reading.status == .approvedLocal || reading.status == .pendingSync || reading.status == .synced) &&
            reading.approvedDigits != nil
        }

        guard relevant.count >= 2 else {
            return []
        }

        let sorted = relevant.sorted(by: { $0.capturedAt < $1.capturedAt })

        for i in 0..<(sorted.count - 1) {
            if sorted[i].capturedAt == sorted[i + 1].capturedAt {
                throw ConsumptionCalculationError.conflictingTimestamp(sorted[i].capturedAt)
            }
        }

        var result: [ConsumptionInterval] = []
        for i in 0..<(sorted.count - 1) {
            let from = sorted[i]
            let to = sorted[i + 1]

            guard let fromApproved = resolveApprovedValue(for: from, meter: meter),
                  let fromDecimal = parseDecimal(fromApproved.uploadValue) else {
                throw ConsumptionCalculationError.invalidReadingValue(from.approvedDigits ?? "")
            }

            guard let toApproved = resolveApprovedValue(for: to, meter: meter),
                  let toDecimal = parseDecimal(toApproved.uploadValue) else {
                throw ConsumptionCalculationError.invalidReadingValue(to.approvedDigits ?? "")
            }

            if toDecimal < fromDecimal {
                throw ConsumptionCalculationError.decreasingValue(from: fromDecimal, to: toDecimal, at: to.capturedAt)
            }

            let amount = toDecimal - fromDecimal
            result.append(
                ConsumptionInterval(
                    fromReadingID: from.id,
                    toReadingID: to.id,
                    start: from.capturedAt,
                    end: to.capturedAt,
                    amount: amount,
                    fromValue: fromDecimal,
                    toValue: toDecimal
                )
            )
        }

        return result
    }

    private static func resolveApprovedValue(for reading: MeterReading, meter: Meter) -> ApprovedReadingValue? {
        guard let digits = reading.approvedDigits else { return nil }
        if let formatted = try? ReadingValidator.approvedDigits(digits, format: meter.format) {
            return formatted
        }
        return try? ReadingValidator.approvedDigits(digits)
    }

    private static func parseDecimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
