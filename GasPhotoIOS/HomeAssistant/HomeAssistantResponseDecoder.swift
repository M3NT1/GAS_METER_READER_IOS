import Foundation

struct HomeAssistantReading: Codable, Equatable, Sendable {
    let id: String
    let revision: Int
    let meterID: String
    let value: String
    let capturedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case meterID = "meter_id"
        case value
        case capturedAt = "captured_at"
    }

    init(id: String, revision: Int, meterID: String, value: String, capturedAt: Date) {
        self.id = id
        self.revision = revision
        self.meterID = meterID
        self.value = value
        self.capturedAt = capturedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decode(Int.self, forKey: .revision)
        meterID = try container.decode(String.self, forKey: .meterID)
        value = try container.decode(String.self, forKey: .value)
        let capturedAtString = try container.decode(String.self, forKey: .capturedAt)
        guard let date = HomeAssistantDateCodec.decode(capturedAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .capturedAt, in: container, debugDescription: "Invalid offset-aware capture time")
        }
        capturedAt = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(revision, forKey: .revision)
        try container.encode(meterID, forKey: .meterID)
        try container.encode(value, forKey: .value)
        try container.encode(HomeAssistantDateCodec.encode(capturedAt), forKey: .capturedAt)
    }
}

enum HomeAssistantResponseError: Error, Equatable {
    case missingServiceResponse
}

enum HomeAssistantResponseDecoder {
    static func verifiedReadings(from data: Data) throws -> [String: HomeAssistantReading] {
        let wrapper = try JSONDecoder().decode(ServiceResponse.self, from: data)
        guard let response = wrapper.serviceResponse else {
            throw HomeAssistantResponseError.missingServiceResponse
        }
        return Dictionary(uniqueKeysWithValues: response.readings.map { ($0.id, $0) })
    }

    private struct ServiceResponse: Decodable {
        let serviceResponse: ReadingsResponse?

        enum CodingKeys: String, CodingKey {
            case serviceResponse = "service_response"
        }
    }

    private struct ReadingsResponse: Decodable {
        let readings: [HomeAssistantReading]
    }
}

enum HomeAssistantDateCodec {
    static func decode(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func encode(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
