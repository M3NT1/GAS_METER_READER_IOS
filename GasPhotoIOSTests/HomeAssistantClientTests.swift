import Foundation
import XCTest
@testable import GasPhotoIOS

final class HomeAssistantClientTests: XCTestCase {
    func testSyncUploadsApprovedReadingThenVerifiesReturnedReading() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_781_815_422.865)
        var reading = MeterReading(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            revision: 2,
            meterID: "gas_main",
            photoID: UUID(),
            capturedAt: capturedAt,
            window: nil,
            proposal: nil,
            approvedDigits: "01817.759",
            status: .pendingSync,
            modelVersion: nil,
            lastSyncError: nil
        )
        reading.approvedDigits = "01817.759"
        let performer = RecordingHomeAssistantPerformer(capturedAt: capturedAt)
        let client = URLSessionHomeAssistantClient(performer: performer)
        let credentials = try HomeAssistantCredentials(
            baseURL: "http://192.168.0.99:8123",
            accessToken: "private-token"
        )

        let verified = try await client.sync(reading: reading, credentials: credentials)

        XCTAssertEqual(verified.meterID, "gas_main")
        XCTAssertEqual(verified.value, "1817.759")
        XCTAssertEqual(verified.capturedAt, capturedAt)
        let requests = await performer.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/services/gas_photo/import_readings")
        XCTAssertEqual(requests[0].url?.query, "return_response")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer private-token")

        // Assert source: "manual_review" was sent
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let readings = try XCTUnwrap(json["readings"] as? [[String: Any]])
        XCTAssertEqual(readings.first?["source"] as? String, "manual_review")
        XCTAssertEqual(readings.first?["meter_id"] as? String, "gas_main")

        XCTAssertEqual(requests[1].url?.path, "/api/services/gas_photo/get_readings")
    }

    func testTestConnectionSuccess() async throws {
        let performer = StubHomeAssistantPerformer { request in
            let path = request.url?.path ?? ""
            if path == "/api" || path == "/api/" {
                return (Data(#"{"message":"API running."}"#.utf8), 200)
            } else if path.contains("get_readings") {
                return (Data(#"{"service_response":{"readings":[]}}"#.utf8), 200)
            }
            return (Data(), 404)
        }
        let client = URLSessionHomeAssistantClient(performer: performer)
        let credentials = try HomeAssistantCredentials(baseURL: "http://192.168.0.99:8123", accessToken: "valid-token")

        let result = try await client.testConnection(credentials: credentials)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.message.contains("Sikeres"))
    }

    func testTestConnectionAuthFailure() async throws {
        let performer = StubHomeAssistantPerformer { request in
            return (Data(#"{"message":"401: Unauthorized"}"#.utf8), 401)
        }
        let client = URLSessionHomeAssistantClient(performer: performer)
        let credentials = try HomeAssistantCredentials(baseURL: "http://192.168.0.99:8123", accessToken: "invalid-token")

        let result = try await client.testConnection(credentials: credentials)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.message.contains("401") || result.message.contains("érvénytelen"))
    }

    func testSyncThrowsServerErrorWithDetailedMessageOn500() async throws {
        let performer = StubHomeAssistantPerformer { request in
            return (Data(#"{"message":"Unsupported meter/source"}"#.utf8), 500)
        }
        let client = URLSessionHomeAssistantClient(performer: performer)
        let credentials = try HomeAssistantCredentials(baseURL: "http://192.168.0.99:8123", accessToken: "valid-token")
        var reading = MeterReading(
            id: UUID(),
            revision: 1,
            meterID: "gas_main",
            photoID: UUID(),
            capturedAt: Date(),
            window: nil,
            proposal: nil,
            approvedDigits: "01889.542",
            status: .pendingSync,
            modelVersion: nil,
            lastSyncError: nil
        )

        do {
            _ = try await client.sync(reading: reading, credentials: credentials)
            XCTFail("Sync should have thrown")
        } catch let error as HomeAssistantClientError {
            switch error {
            case let .serverError(statusCode, message):
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(message, "Unsupported meter/source")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testServerError500TroubleProducesUserFriendlyHungarianMessage() async throws {
        let performer = StubHomeAssistantPerformer { request in
            return (Data("500 Internal Server Error\n\nServer got itself in trouble".utf8), 500)
        }
        let client = URLSessionHomeAssistantClient(performer: performer)
        let credentials = try HomeAssistantCredentials(baseURL: "http://192.168.0.99:8123", accessToken: "valid-token")
        let reading = MeterReading(
            id: UUID(),
            revision: 1,
            meterID: "gas_main",
            photoID: UUID(),
            capturedAt: Date(),
            window: nil,
            proposal: nil,
            approvedDigits: "00055.552",
            status: .pendingSync,
            modelVersion: nil,
            lastSyncError: nil
        )

        do {
            _ = try await client.sync(reading: reading, credentials: credentials)
            XCTFail("Sync should have thrown")
        } catch let error as HomeAssistantClientError {
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("500"))
            XCTAssertTrue(desc.contains("nem foroghat visszafelé") || desc.contains("kisebb az előzőnél"))
            XCTAssertFalse(desc.contains("trouble"))
        }
    }

    func testTranslateServerMessage() {
        let decrease = HomeAssistantClientError.translateServerMessage("Meter decrease requires review")
        XCTAssertTrue(decrease.contains("nem lehet kisebb"))

        let rate = HomeAssistantClientError.translateServerMessage("Implausible consumption rate")
        XCTAssertTrue(rate.contains("fogyasztás"))
    }
}

private actor RecordingHomeAssistantPerformer: HomeAssistantRequestPerforming {
    private let capturedAt: Date
    private(set) var requests: [URLRequest] = []

    init(capturedAt: Date) {
        self.capturedAt = capturedAt
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let reading: [String: Any]
        if let readings = object["readings"] as? [[String: Any]] {
            reading = try XCTUnwrap(readings.first)
        } else {
            let ids = try XCTUnwrap(object["ids"] as? [String])
            reading = [
                "id": try XCTUnwrap(ids.first),
                "revision": 2,
                "meter_id": "gas_main",
                "value": "1817.759",
                "captured_at": HomeAssistantDateCodec.encode(capturedAt)
            ]
        }
        let response: [String: Any] = ["service_response": ["readings": [reading]]]
        let data = try JSONSerialization.data(withJSONObject: response)
        return (data, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class StubHomeAssistantPerformer: HomeAssistantRequestPerforming, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) throws -> (Data, Int)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, Int)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(url: request.url ?? URL(string: "http://localhost")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
