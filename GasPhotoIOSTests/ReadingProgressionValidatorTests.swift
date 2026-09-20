import XCTest
@testable import GasPhotoIOS

final class ReadingProgressionValidatorTests: XCTestCase {
    private let waterMeter1 = Meter(
        id: "water_kitchen",
        name: "Konyhai vízóra",
        kind: .water,
        format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
        recognition: .manual,
        isArchived: false
    )

    private let waterMeter2 = Meter(
        id: "water_bathroom",
        name: "Fürdőszobai vízóra",
        kind: .water,
        format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
        recognition: .manual,
        isArchived: false
    )

    func testTwoSeparateMetersDoNotInterfereWithEachOther() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        // Water meter 1 has reading 100.000 at t1
        let readingMeter1 = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: waterMeter1.id,
            photoID: UUID(),
            capturedAt: t1,
            window: nil,
            proposal: nil,
            approvedDigits: "00100.000",
            status: .approvedLocal,
            modelVersion: nil,
            lastSyncError: nil
        )

        // Water meter 2 candidate has reading 5.000 at t2
        let candidateMeter2 = MeterReading(
            id: UUID(),
            revision: 0,
            meterID: waterMeter2.id,
            photoID: UUID(),
            capturedAt: t2,
            window: nil,
            proposal: nil,
            approvedDigits: nil,
            status: .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )

        let candidateApproved = try ReadingValidator.approvedDigits("00005.000", format: waterMeter2.format)

        XCTAssertNoThrow(
            try ReadingProgressionValidator.validate(
                candidate: candidateMeter2,
                approved: candidateApproved,
                meter: waterMeter2,
                allReadings: [readingMeter1]
            )
        )
    }

    func testIntermediateReadingBetweenPriorAndLaterIsAccepted() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        let prior = makeReading(meterID: waterMeter1.id, time: t1, digits: "00010.000")
        let later = makeReading(meterID: waterMeter1.id, time: t3, digits: "00020.000")

        let candidate = makeReading(meterID: waterMeter1.id, time: t2, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00015.000", format: waterMeter1.format)

        XCTAssertNoThrow(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [prior, later]
            )
        )
    }

    func testDecreasingReadingComparedToPriorThrowsError() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        let prior = makeReading(meterID: waterMeter1.id, time: t1, digits: "00010.000")
        let candidate = makeReading(meterID: waterMeter1.id, time: t2, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00005.000", format: waterMeter1.format)

        XCTAssertThrowsError(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [prior]
            )
        ) { error in
            guard let progressionError = error as? ReadingProgressionError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            if case let .decreasingValue(cand, pr, unit) = progressionError {
                XCTAssertEqual(cand, "5.000")
                XCTAssertEqual(pr, "10.000")
                XCTAssertEqual(unit, "m³")
            } else {
                XCTFail("Expected decreasingValue error, got \(progressionError)")
            }
        }
    }

    func testIncreasingReadingComparedToLaterThrowsError() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        let later = makeReading(meterID: waterMeter1.id, time: t2, digits: "00020.000")
        let candidate = makeReading(meterID: waterMeter1.id, time: t1, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00025.000", format: waterMeter1.format)

        XCTAssertThrowsError(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [later]
            )
        ) { error in
            guard let progressionError = error as? ReadingProgressionError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            if case let .increasingValueComparedToLater(cand, lat, unit) = progressionError {
                XCTAssertEqual(cand, "25.000")
                XCTAssertEqual(lat, "20.000")
                XCTAssertEqual(unit, "m³")
            } else {
                XCTFail("Expected increasingValueComparedToLater error, got \(progressionError)")
            }
        }
    }

    func testDuplicateTimestampThrowsDuplicateError() throws {
        let t1 = Date(timeIntervalSince1970: 1000)

        let existing = makeReading(meterID: waterMeter1.id, time: t1, digits: "00010.000")
        let candidate = makeReading(meterID: waterMeter1.id, time: t1, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00010.000", format: waterMeter1.format)

        XCTAssertThrowsError(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [existing]
            )
        ) { error in
            guard let progressionError = error as? ReadingProgressionError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            if case .duplicateTimestamp = progressionError {
                // Expected
            } else {
                XCTFail("Expected duplicateTimestamp error, got \(progressionError)")
            }
        }
    }

    func testConflictingTimestampThrowsConflictError() throws {
        let t1 = Date(timeIntervalSince1970: 1000)

        let existing = makeReading(meterID: waterMeter1.id, time: t1, digits: "00010.000")
        let candidate = makeReading(meterID: waterMeter1.id, time: t1, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00012.000", format: waterMeter1.format)

        XCTAssertThrowsError(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [existing]
            )
        ) { error in
            guard let progressionError = error as? ReadingProgressionError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            if case .conflictingTimestamp = progressionError {
                // Expected
            } else {
                XCTFail("Expected conflictingTimestamp error, got \(progressionError)")
            }
        }
    }

    func testSameValueAtLaterTimestampIsPermitted() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        let prior = makeReading(meterID: waterMeter1.id, time: t1, digits: "00010.000")
        let candidate = makeReading(meterID: waterMeter1.id, time: t2, digits: nil)
        let candidateApproved = try ReadingValidator.approvedDigits("00010.000", format: waterMeter1.format)

        XCTAssertNoThrow(
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: candidateApproved,
                meter: waterMeter1,
                allReadings: [prior]
            )
        )
    }

    private func makeReading(meterID: String, time: Date, digits: String?) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: meterID,
            photoID: UUID(),
            capturedAt: time,
            window: nil,
            proposal: nil,
            approvedDigits: digits,
            status: digits != nil ? .approvedLocal : .needsReview,
            modelVersion: nil,
            lastSyncError: nil
        )
    }
}
