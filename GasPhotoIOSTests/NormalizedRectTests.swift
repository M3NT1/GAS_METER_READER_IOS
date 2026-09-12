import XCTest
@testable import GasPhotoIOS

final class NormalizedRectTests: XCTestCase {
    func testGeometryProperties() {
        let rect = NormalizedRect(left: 0.20, top: 0.40, right: 0.80, bottom: 0.45)

        XCTAssertEqual(rect.width, 0.60, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.05, accuracy: 0.0001)
        XCTAssertEqual(rect.centerX, 0.50, accuracy: 0.0001)
        XCTAssertEqual(rect.centerY, 0.425, accuracy: 0.0001)
        XCTAssertEqual(rect.aspectRatio, 12.0, accuracy: 0.0001)
    }

    func testScaleDownToCustomMinimums() {
        let rect = NormalizedRect(left: 0.40, top: 0.40, right: 0.60, bottom: 0.50)
        // Scale down drastically (0.01x)
        let shrunk = rect.scaled(by: 0.01, minWidth: 0.02, minHeight: 0.005)

        XCTAssertGreaterThanOrEqual(shrunk.width, 0.02)
        XCTAssertGreaterThanOrEqual(shrunk.height, 0.005)
        XCTAssertEqual(shrunk.centerX, 0.50, accuracy: 0.0001)
        XCTAssertEqual(shrunk.centerY, 0.45, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(shrunk.left, 0.0)
        XCTAssertLessThanOrEqual(shrunk.right, 1.0)
        XCTAssertGreaterThanOrEqual(shrunk.top, 0.0)
        XCTAssertLessThanOrEqual(shrunk.bottom, 1.0)
    }

    func testScaleUpStaysWithinNormalizedBounds() {
        let rect = NormalizedRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95)
        // Scale up by 2x
        let expanded = rect.scaled(by: 2.0, minWidth: 0.02, minHeight: 0.005)

        XCTAssertGreaterThanOrEqual(expanded.left, 0.0)
        XCTAssertLessThanOrEqual(expanded.right, 1.0)
        XCTAssertGreaterThanOrEqual(expanded.top, 0.0)
        XCTAssertLessThanOrEqual(expanded.bottom, 1.0)
    }

    func testVeryThinWindowAllowed() {
        // A thin gas meter roller strip representing 1.5% height and 25% width
        let thinRect = NormalizedRect(left: 0.35, top: 0.48, right: 0.60, bottom: 0.495)

        XCTAssertEqual(thinRect.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(thinRect.height, 0.015, accuracy: 0.0001)
        XCTAssertGreaterThan(thinRect.height, 0.0005)
        XCTAssertGreaterThan(thinRect.width, 0.005)
    }

    func testUltraThinWindowDownTo5Pixels() {
        // A 5-pixel high window on a 4000px image is 0.00125
        let fivePxRect = NormalizedRect(left: 0.20, top: 0.450, right: 0.80, bottom: 0.45125)
        XCTAssertEqual(fivePxRect.height, 0.00125, accuracy: 0.00001)

        let shrunk = fivePxRect.scaled(by: 0.1, minWidth: 0.005, minHeight: 0.0005)
        XCTAssertEqual(shrunk.height, 0.0005, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(shrunk.height, 0.0005)
    }
}
