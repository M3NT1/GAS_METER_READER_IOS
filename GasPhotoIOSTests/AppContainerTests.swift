import XCTest
@testable import GasPhotoIOS

@MainActor
final class AppContainerTests: XCTestCase {
    func testLiveContainerUsesConcreteServices() {
        let container = AppContainer.live()

        XCTAssertFalse(container.readingRepository is InMemoryReadingRepository)
        XCTAssertFalse(container.inferenceService is StubInferenceService)
    }
}
