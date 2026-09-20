import Foundation

enum ReadingProgressionError: LocalizedError, Equatable {
    case duplicateTimestamp(Date)
    case conflictingTimestamp(Date)
    case decreasingValue(candidate: String, prior: String, unit: String)
    case increasingValueComparedToLater(candidate: String, later: String, unit: String)
    case invalidReadingValue(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateTimestamp(date):
            let formatted = date.formatted(date: .abbreviated, time: .standard)
            return "Már létezik rögzített leolvasás ezzel a pontos időponttal (\(formatted))."
        case let .conflictingTimestamp(date):
            let formatted = date.formatted(date: .abbreviated, time: .standard)
            return "Ütköző leolvasás található ugyanezzel az időponttal (\(formatted))."
        case let .decreasingValue(candidate, prior, unit):
            return "A megadott állás (\(candidate) \(unit)) kisebb, mint a korábbi rögzített állás (\(prior) \(unit)). A mérőóra számlálója nem csökkenhet visszafelé! Ellenőrizd a beírt számjegyeket."
        case let .increasingValueComparedToLater(candidate, later, unit):
            return "A megadott állás (\(candidate) \(unit)) nagyobb, mint a későbbi rögzített állás (\(later) \(unit)). Ellenőrizd a dátumot vagy a számjegyeket!"
        case let .invalidReadingValue(val):
            return "A leolvasás értéke érvénytelen: \(val)"
        }
    }
}

enum ReadingProgressionValidator {
    static func validate(
        candidate: MeterReading,
        approved: ApprovedReadingValue,
        meter: Meter,
        allReadings: [MeterReading]
    ) throws {
        guard let candidateDecimal = parseDecimal(approved.uploadValue) else {
            throw ReadingProgressionError.invalidReadingValue(approved.uploadValue)
        }

        let relevantReadings = allReadings.filter {
            $0.meterID == meter.id &&
            $0.id != candidate.id &&
            $0.approvedDigits != nil
        }

        // Check for same timestamp (duplicate or conflict)
        for other in relevantReadings where other.capturedAt == candidate.capturedAt {
            let otherApproved = resolveApprovedValue(for: other, meter: meter)
            if otherApproved?.uploadValue == approved.uploadValue {
                throw ReadingProgressionError.duplicateTimestamp(candidate.capturedAt)
            } else {
                throw ReadingProgressionError.conflictingTimestamp(candidate.capturedAt)
            }
        }

        // Check earlier readings
        let earlierReadings = relevantReadings.filter { $0.capturedAt < candidate.capturedAt }
        if let latestPrior = earlierReadings.max(by: { $0.capturedAt < $1.capturedAt }),
           let priorApproved = resolveApprovedValue(for: latestPrior, meter: meter),
           let priorDecimal = parseDecimal(priorApproved.uploadValue) {
            if candidateDecimal < priorDecimal {
                throw ReadingProgressionError.decreasingValue(
                    candidate: approved.uploadValue,
                    prior: priorApproved.uploadValue,
                    unit: meter.kind.unitSymbol
                )
            }
        }

        // Check later readings
        let laterReadings = relevantReadings.filter { $0.capturedAt > candidate.capturedAt }
        if let earliestLater = laterReadings.min(by: { $0.capturedAt < $1.capturedAt }),
           let laterApproved = resolveApprovedValue(for: earliestLater, meter: meter),
           let laterDecimal = parseDecimal(laterApproved.uploadValue) {
            if candidateDecimal > laterDecimal {
                throw ReadingProgressionError.increasingValueComparedToLater(
                    candidate: approved.uploadValue,
                    later: laterApproved.uploadValue,
                    unit: meter.kind.unitSymbol
                )
            }
        }
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
