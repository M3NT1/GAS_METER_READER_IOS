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
        XCTAssertEqual(requests[1].url?.path, "/api/services/gas_photo/get_readings")
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
