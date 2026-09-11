import XCTest
@testable import GasPhotoIOS

final class HomeAssistantResponseDecoderTests: XCTestCase {
    func testVerifiedReadingsDecodesServiceResponseWrapper() throws {
        let identifier = String(repeating: "a", count: 64)
        let data = Data("""
        {
          "service_response": {
            "readings": [{
              "id": "\(identifier)",
              "revision": 1,
              "meter_id": "gas_main",
              "value": "1817.759",
              "captured_at": "2026-06-18T22:43:42.865+02:00"
            }]
          }
        }
        """.utf8)

        let readings = try HomeAssistantResponseDecoder.verifiedReadings(from: data)

        XCTAssertEqual(readings[identifier]?.value, "1817.759")
        XCTAssertEqual(readings[identifier]?.meterID, "gas_main")
        XCTAssertEqual(readings[identifier]?.revision, 1)
    }
}
