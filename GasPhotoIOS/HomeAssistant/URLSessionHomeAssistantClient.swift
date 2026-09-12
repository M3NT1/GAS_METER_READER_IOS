import CryptoKit
import Foundation

struct ConnectionTestResult: Equatable, Sendable {
    let isSuccess: Bool
    let message: String
}

protocol HomeAssistantClient: Sendable {
    func sync(reading: MeterReading, credentials: HomeAssistantCredentials) async throws -> HomeAssistantReading
    func testConnection(credentials: HomeAssistantCredentials) async throws -> ConnectionTestResult
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

enum HomeAssistantClientError: LocalizedError, Equatable {
    case readingNotApproved
    case invalidResponse
    case unexpectedStatusCode(Int)
    case serverError(statusCode: Int, message: String)
    case verificationMissing
    case verificationMismatch

    var errorDescription: String? {
        switch self {
        case .readingNotApproved:
            return "A leolvasás még nincs jóváhagyva."
        case .invalidResponse:
            return "Érvénytelen válasz érkezett a Home Assistant szervertől."
        case let .unexpectedStatusCode(code):
            return "Váratlan HTTP státuszkód: \(code)."
        case let .serverError(code, message):
            if code == 401 {
                return "Hitelesítési hiba (HTTP 401): A Home Assistant hozzáférési token érvénytelen vagy lejárt."
            } else if code == 404 {
                return "Szolgáltatás hiba (HTTP 404): A gas_photo komponens nem található a Home Assistantban."
            } else if code == 500 && (message.localizedCaseInsensitiveContains("trouble") || message.localizedCaseInsensitiveContains("internal server error")) {
                return "Home Assistant szerverhiba (500): A szerver elutasította a leolvasást. Leggyakoribb ok: a megadott óraállás kisebb az előzőnél (az óra nem foroghat visszafelé), vagy a számított fogyasztás meghaladja a megengedett maximumot."
            } else {
                let translated = Self.translateServerMessage(message)
                return "Home Assistant hiba (\(code)): \(translated)"
            }
        case .verificationMissing:
            return "Az ellenőrzés sikertelen: a Home Assistant nem adta vissza a mentett értéket."
        case .verificationMismatch:
            return "Az ellenőrzés sikertelen: a szerveren lévő adat eltér a feltöltött leolvasástól."
        }
    }

    static func translateServerMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("Meter decrease requires review") {
            return "A leolvasott érték nem lehet kisebb a korábbi óraállásnál (visszafelé tekerés vagy elgépelés)."
        }
        if trimmed.localizedCaseInsensitiveContains("Implausible consumption rate") {
            return "A két leolvasás közötti fogyasztás valószínűtlenül magas az eltelt időhöz képest."
        }
        if trimmed.localizedCaseInsensitiveContains("Future capture time") {
            return "A rögzítés időpontja nem lehet a jövőben."
        }
        if trimmed.localizedCaseInsensitiveContains("Conflicting capture timestamp") {
            return "Erre az időpontra már létezik egy eltérő állású leolvasás."
        }
        if trimmed.localizedCaseInsensitiveContains("Stale or conflicting revision") {
            return "A leolvasás verziója elavult vagy ütközik a szerveren lévő rekorddal."
        }
        return trimmed
    }
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
            capturedAt: HomeAssistantDateCodec.encode(reading.capturedAt),
            source: "manual_review"
        )

        let importRequest = try request(
            endpoint: "import_readings",
            body: ImportBody(readings: [upload]),
            credentials: credentials
        )

        let verificationRequest = try request(
            endpoint: "get_readings",
            body: VerificationBody(ids: [externalID]),
            credentials: credentials
        )

        do {
            _ = try await perform(importRequest)
        } catch let error as HomeAssistantClientError {
            // Ha revízió ütközés van (pl. egy korábbi kísérletben már bekerült a rekord a szerverre),
            // ellenőrizzük, hogy a szerveren tárolt adat már egyezik-e a jóváhagyottal
            if case let .serverError(_, message) = error, message.localizedCaseInsensitiveContains("revision") {
                if let checkData = try? await perform(verificationRequest),
                   let existing = try? HomeAssistantResponseDecoder.verifiedReadings(from: checkData)[externalID],
                   existing.value == value,
                   existing.meterID == reading.meterID,
                   abs(existing.capturedAt.timeIntervalSince(reading.capturedAt)) < 1.0 {
                    return existing
                }
            }
            throw error
        }

        let verifiedData = try await perform(verificationRequest)
        guard let verified = try HomeAssistantResponseDecoder.verifiedReadings(from: verifiedData)[externalID] else {
            throw HomeAssistantClientError.verificationMissing
        }
        guard verified.revision >= reading.revision,
              verified.meterID == reading.meterID,
              verified.value == value,
              abs(verified.capturedAt.timeIntervalSince(reading.capturedAt)) < 1.0 else {
            throw HomeAssistantClientError.verificationMismatch
        }
        return verified
    }

    func testConnection(credentials: HomeAssistantCredentials) async throws -> ConnectionTestResult {
        var apiRequest = URLRequest(url: credentials.baseURL.appendingPathComponent("api/"))
        apiRequest.httpMethod = "GET"
        apiRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let apiData: Data
        let apiResponse: HTTPURLResponse
        do {
            (apiData, apiResponse) = try await performer.data(for: apiRequest)
        } catch {
            return ConnectionTestResult(
                isSuccess: false,
                message: "Nem sikerült kapcsolódni a szerverhez: \(error.localizedDescription)"
            )
        }

        guard (200 ... 299).contains(apiResponse.statusCode) else {
            if apiResponse.statusCode == 401 {
                return ConnectionTestResult(
                    isSuccess: false,
                    message: "Hitelesítési hiba (HTTP 401): A megadott hozzáférési token érvénytelen vagy lejárt."
                )
            } else {
                let msg = Self.extractErrorMessage(from: apiData, statusCode: apiResponse.statusCode)
                return ConnectionTestResult(
                    isSuccess: false,
                    message: "Home Assistant hiba (HTTP \(apiResponse.statusCode)): \(msg)"
                )
            }
        }

        do {
            let checkRequest = try request(
                endpoint: "get_readings",
                body: VerificationBody(ids: []),
                credentials: credentials
            )
            let verifiedData = try await perform(checkRequest)
            _ = try HomeAssistantResponseDecoder.verifiedReadings(from: verifiedData)
            return ConnectionTestResult(
                isSuccess: true,
                message: "Sikeres kapcsolat! A Home Assistant API és a gas_photo integráció aktív."
            )
        } catch {
            return ConnectionTestResult(
                isSuccess: false,
                message: "A Home Assistant válaszol, de a gas_photo szolgáltatás hibát jelzett: \(error.localizedDescription)"
            )
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await performer.data(for: request)
        guard (200 ... 299).contains(response.statusCode) else {
            let message = Self.extractErrorMessage(from: data, statusCode: response.statusCode)
            throw HomeAssistantClientError.serverError(statusCode: response.statusCode, message: message)
        }
        return data
    }

    private static func extractErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["message"] as? String, !msg.isEmpty {
                return msg
            }
            if let err = json["error"] as? String, !err.isEmpty {
                return err
            }
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
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
        let source: String

        enum CodingKeys: String, CodingKey {
            case id, revision, value, source
            case meterID = "meter_id"
            case capturedAt = "captured_at"
        }
    }
}
