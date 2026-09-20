import XCTest
@testable import GasPhotoIOS

final class MeterFormatTests: XCTestCase {
    func testFormatRejectsOutOfRangeWidthsAtCreation() {
        XCTAssertNil(MeterFormat(validating: 0, fractionalDigits: 3))
        XCTAssertNil(MeterFormat(validating: 6, fractionalDigits: 4))
    }

    func testManualElectricityNormalizesHungarianDecimalInput() throws {
        let value = try ReadingValidator.approvedDigits(
            "12,45",
            format: MeterFormat(integerDigits: 6, fractionalDigits: 3)
        )

        XCTAssertEqual(value.displayValue, "000012.450")
        XCTAssertEqual(value.uploadValue, "12.450")
    }

    func testManualWholeNumberMeterKeepsCanonicalInteger() throws {
        let value = try ReadingValidator.approvedDigits(
            "42",
            format: MeterFormat(integerDigits: 5, fractionalDigits: 0)
        )

        XCTAssertEqual(value.displayValue, "00042")
        XCTAssertEqual(value.uploadValue, "42")
    }

    func testManualFormatRejectsInvalidDecimalInput() {
        let format = MeterFormat(integerDigits: 6, fractionalDigits: 3)

        for input in ["12.3456", "12.3.4", "-12.3", "١٢.٣", "1234567.0"] {
            XCTAssertThrowsError(try ReadingValidator.approvedDigits(input, format: format))
        }
    }
}
