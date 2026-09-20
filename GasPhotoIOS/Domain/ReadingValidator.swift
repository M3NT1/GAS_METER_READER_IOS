import Foundation

enum ReadingValidationError: Error, Equatable {
    case invalidDisplayValue
    case invalidMeterFormat
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

    static func approvedDigits(_ input: String, format: MeterFormat) throws -> ApprovedReadingValue {
        guard format.isValid else {
            throw ReadingValidationError.invalidMeterFormat
        }

        let normalizedInput = input.replacingOccurrences(of: ",", with: ".")
        let parts = normalizedInput.split(separator: ".", omittingEmptySubsequences: false)
        let expectedPartCount = format.fractionalDigits == 0 ? 1 : 2
        guard parts.count == expectedPartCount,
              !parts[0].isEmpty,
              parts[0].count <= format.integerDigits,
              parts[0].allSatisfy(isASCIIDigit),
              (format.fractionalDigits == 0 ||
                (parts[1].count <= format.fractionalDigits && parts[1].allSatisfy(isASCIIDigit))) else {
            throw ReadingValidationError.invalidDisplayValue
        }

        let integer = String(parts[0])
        let fractional = format.fractionalDigits == 0
            ? ""
            : String(parts[1]).padding(toLength: format.fractionalDigits, withPad: "0", startingAt: 0)
        let displayInteger = integer.padding(
            toLength: format.integerDigits,
            withPad: "0",
            startingAt: 0,
            left: true
        )
        let uploadInteger = integer.drop(while: { $0 == "0" })
        let normalizedUploadInteger = uploadInteger.isEmpty ? "0" : String(uploadInteger)
        let displayValue = format.fractionalDigits == 0
            ? displayInteger
            : "\(displayInteger).\(fractional)"
        let uploadValue = format.fractionalDigits == 0
            ? normalizedUploadInteger
            : "\(normalizedUploadInteger).\(fractional)"
        return ApprovedReadingValue(displayValue: displayValue, uploadValue: uploadValue)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
}

private extension String {
    func padding(toLength length: Int, withPad pad: String, startingAt index: Int, left: Bool) -> String {
        guard count < length else { return self }
        let padding = String(repeating: pad, count: length - count)
        return left ? padding + self : self + padding
    }
}
