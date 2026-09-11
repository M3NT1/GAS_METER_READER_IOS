import CryptoKit
import Foundation

protocol HomeAssistantClient: Sendable {
    func sync(reading: MeterReading, credentials: HomeAssistantCredentials) async throws -> HomeAssistantReading
}

protocol HomeAssistantRequestPerforming: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionRequestPerformer: HomeAssistantRequestPerforming, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeAssistantClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

enum HomeAssistantClientError: Error, Equatable {
    case readingNotApproved
    case invalidResponse
    case unexpectedStatusCode(Int)
    case verificationMissing
    case verificationMismatch
}

final class URLSessionHomeAssistantClient: HomeAssistantClient, @unchecked Sendable {
    private let performer: any HomeAssistantRequestPerforming

    init(performer: any HomeAssistantRequestPerforming = URLSessionRequestPerformer()) {
        self.performer = performer
    }

    func sync(reading: MeterReading, credentials: HomeAssistantCredentials) async throws -> HomeAssistantReading {
        guard let displayValue = reading.approvedDigits else {
            throw HomeAssistantClientError.readingNotApproved
        }
        let value = try ReadingValidator.approvedDigits(displayValue).uploadValue
        let externalID = Self.externalID(for: reading.id)
        let upload = UploadReading(
            id: externalID,
            revision: reading.revision,
            meterID: reading.meterID,
            value: value,
            capturedAt: HomeAssistantDateCodec.encode(reading.capturedAt)
        )

        let importRequest = try request(
            endpoint: "import_readings",
            body: ImportBody(readings: [upload]),
            credentials: credentials
        )
        _ = try await perform(importRequest)

        let verificationRequest = try request(
            endpoint: "get_readings",
            body: VerificationBody(ids: [externalID]),
            credentials: credentials
        )
        let verifiedData = try await perform(verificationRequest)
        guard let verified = try HomeAssistantResponseDecoder.verifiedReadings(from: verifiedData)[externalID] else {
            throw HomeAssistantClientError.verificationMissing
        }
        guard verified.revision == reading.revision,
              verified.meterID == reading.meterID,
              verified.value == value,
              verified.capturedAt == reading.capturedAt else {
            throw HomeAssistantClientError.verificationMismatch
        }
        return verified
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await performer.data(for: request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw HomeAssistantClientError.unexpectedStatusCode(response.statusCode)
        }
        return data
    }

    private func request<Body: Encodable>(
        endpoint: String,
        body: Body,
        credentials: HomeAssistantCredentials
    ) throws -> URLRequest {
        let serviceURL = credentials.baseURL
            .appendingPathComponent("api/services/gas_photo")
            .appendingPathComponent(endpoint)
        var components = URLComponents(url: serviceURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "return_response", value: nil)]
        guard let url = components?.url else {
            throw HomeAssistantClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func externalID(for id: UUID) -> String {
        SHA256.hash(data: Data(id.uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct ImportBody: Encodable {
        let readings: [UploadReading]
    }

    private struct VerificationBody: Encodable {
        let ids: [String]
    }

    private struct UploadReading: Encodable {
        let id: String
        let revision: Int
        let meterID: String
        let value: String
        let capturedAt: String

        enum CodingKeys: String, CodingKey {
            case id, revision, value
            case meterID = "meter_id"
            case capturedAt = "captured_at"
        }
    }
}
