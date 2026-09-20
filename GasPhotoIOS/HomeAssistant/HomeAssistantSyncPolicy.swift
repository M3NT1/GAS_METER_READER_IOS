import Foundation

enum HomeAssistantSyncPolicy {
    static func supports(_ meter: Meter) -> Bool {
        meter.id == "gas_main" &&
            meter.kind == .gas &&
            meter.format == MeterFormat(integerDigits: 5, fractionalDigits: 3) &&
            meter.recognition == .legacyGas8
    }

    static func mayStartRequest(enabled: Bool, meter: Meter) -> Bool {
        enabled && supports(meter)
    }
}
