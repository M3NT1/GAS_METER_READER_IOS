import Foundation

enum ReadingValidationError: Error, Equatable {
    case invalidDisplayValue
}

enum ReadingValidator {
    static func approvedDigits(_ displayValue: String) throws -> ApprovedReadingValue {
        let parts = displayValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 5,
              parts[1].count == 3,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            throw ReadingValidationError.invalidDisplayValue
        }

        let integerPart = String(parts[0])
        let normalizedInteger = integerPart.drop(while: { $0 == "0" })
        let uploadInteger = normalizedInteger.isEmpty ? "0" : String(normalizedInteger)
        return ApprovedReadingValue(
            displayValue: displayValue,
            uploadValue: "\(uploadInteger).\(parts[1])"
        )
    }
}
