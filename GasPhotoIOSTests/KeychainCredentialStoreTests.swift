import XCTest
@testable import GasPhotoIOS

final class KeychainCredentialStoreTests: XCTestCase {
    func testSaveLoadAndClearCredentials() async throws {
        let store = KeychainCredentialStore(service: "hu.m3nt1.gasphoto.tests.\(UUID().uuidString)")
        let credentials = try HomeAssistantCredentials(
            baseURL: "http://192.168.0.99:8123",
            accessToken: "test-token"
        )

        try await store.save(credentials)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, credentials)
        try await store.clear()
        let cleared = try await store.load()
        XCTAssertNil(cleared)
    }
}
