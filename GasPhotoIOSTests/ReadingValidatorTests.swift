import XCTest
@testable import GasPhotoIOS

final class ReadingValidatorTests: XCTestCase {
    func testApprovalPreservesEightDigitsButNormalizesUploadValue() throws {
        let value = try ReadingValidator.approvedDigits("01817.759")

        XCTAssertEqual(value.displayValue, "01817.759")
        XCTAssertEqual(value.uploadValue, "1817.759")
    }

    func testApprovalRejectsWrongDigitShape() {
        XCTAssertThrowsError(try ReadingValidator.approvedDigits("1817.759"))
    }

    func testApprovalKeepsOneZeroForAnAllZeroIntegerPart() throws {
        let value = try ReadingValidator.approvedDigits("00000.001")

        XCTAssertEqual(value.uploadValue, "0.001")
    }
}
