import Foundation

enum MeterKind: String, Codable, CaseIterable, Sendable {
    case electricity
    case gas
    case water

    var unitSymbol: String {
        switch self {
        case .electricity:
            "kWh"
        case .gas, .water:
            "m³"
        }
    }
}

enum RecognitionProfile: String, Codable, Sendable {
    case legacyGas8
    case manual
}

struct MeterFormat: Codable, Equatable, Sendable {
    let integerDigits: Int
    let fractionalDigits: Int

    init(integerDigits: Int, fractionalDigits: Int) {
        self.integerDigits = integerDigits
        self.fractionalDigits = fractionalDigits
    }

    init?(validating integerDigits: Int, fractionalDigits: Int) {
        let format = MeterFormat(integerDigits: integerDigits, fractionalDigits: fractionalDigits)
        guard format.isValid else { return nil }
        self = format
    }

    var isValid: Bool {
        (1...9).contains(integerDigits) && (0...3).contains(fractionalDigits)
    }
}

struct Meter: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    let kind: MeterKind
    let format: MeterFormat
    let recognition: RecognitionProfile
    var isArchived: Bool
}

extension Meter {
    static let defaultGas = Meter(
        id: "gas_main",
        name: "Gázóra",
        kind: .gas,
        format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
        recognition: .legacyGas8,
        isArchived: false
    )
}

