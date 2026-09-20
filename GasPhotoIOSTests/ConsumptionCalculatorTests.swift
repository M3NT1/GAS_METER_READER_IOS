import XCTest
@testable import GasPhotoIOS

final class ConsumptionCalculatorTests: XCTestCase {
    private let gasMeter = Meter(
        id: "gas_main",
        name: "Gázóra",
        kind: .gas,
        format: MeterFormat(integerDigits: 5, fractionalDigits: 3),
        recognition: .legacyGas8,
        isArchived: false
    )

    private let waterMeter = Meter(
        id: "water_main",
        name: "Vízóra",
        kind: .water,
        format: MeterFormat(integerDigits: 4, fractionalDigits: 3),
        recognition: .manual,
        isArchived: false
    )

    func testSequentialReadingsProduceCorrectIntervals() throws {
        let baseDate = Date(timeIntervalSince1970: 1_770_000_000)
        let r1 = makeReading(meterID: "gas_main", date: baseDate, digits: "00100.000", status: .approvedLocal)
        let r2 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 5), digits: "00102.350", status: .pendingSync)
        let r3 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 10), digits: "00103.000", status: .synced)

        let intervals = try ConsumptionCalculator.intervals(readings: [r1, r2, r3], meter: gasMeter)

        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0].amount, Decimal(string: "2.350"))
        XCTAssertEqual(intervals[0].fromReadingID, r1.id)
        XCTAssertEqual(intervals[0].toReadingID, r2.id)
        XCTAssertEqual(intervals[0].start, r1.capturedAt)
        XCTAssertEqual(intervals[0].end, r2.capturedAt)

        XCTAssertEqual(intervals[1].amount, Decimal(string: "0.650"))
        XCTAssertEqual(intervals[1].fromReadingID, r2.id)
        XCTAssertEqual(intervals[1].toReadingID, r3.id)
        XCTAssertEqual(intervals[1].start, r2.capturedAt)
        XCTAssertEqual(intervals[1].end, r3.capturedAt)
    }

    func testMixedMetersAndUnapprovedReadingsAreIgnored() throws {
        let baseDate = Date(timeIntervalSince1970: 1_770_000_000)
        let gas1 = makeReading(meterID: "gas_main", date: baseDate, digits: "00100.000", status: .approvedLocal)
        let water = makeReading(meterID: "water_main", date: baseDate.addingTimeInterval(86400 * 2), digits: "0050.000", status: .approvedLocal)
        let gasUnapproved = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 3), digits: "00101.000", status: .needsReview)
        let gas2 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 5), digits: "00102.350", status: .synced)

        let gasIntervals = try ConsumptionCalculator.intervals(
            readings: [gas1, water, gasUnapproved, gas2],
            meter: gasMeter
        )

        XCTAssertEqual(gasIntervals.count, 1)
        XCTAssertEqual(gasIntervals[0].fromReadingID, gas1.id)
        XCTAssertEqual(gasIntervals[0].toReadingID, gas2.id)
        XCTAssertEqual(gasIntervals[0].amount, Decimal(string: "2.350"))

        let waterIntervals = try ConsumptionCalculator.intervals(
            readings: [gas1, water, gasUnapproved, gas2],
            meter: waterMeter
        )
        XCTAssertTrue(waterIntervals.isEmpty)
    }

    func testEmptyOrSingleReadingReturnsEmptyIntervals() throws {
        let empty = try ConsumptionCalculator.intervals(readings: [], meter: gasMeter)
        XCTAssertTrue(empty.isEmpty)

        let single = makeReading(meterID: "gas_main", date: .now, digits: "00100.000", status: .approvedLocal)
        let singleResult = try ConsumptionCalculator.intervals(readings: [single], meter: gasMeter)
        XCTAssertTrue(singleResult.isEmpty)
    }

    func testIntermediateInsertionAndDeletion() throws {
        let baseDate = Date(timeIntervalSince1970: 1_770_000_000)
        let r1 = makeReading(meterID: "gas_main", date: baseDate, digits: "00100.000", status: .approvedLocal)
        let r3 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 10), digits: "00102.350", status: .approvedLocal)

        // Baseline: 2 readings -> 1 interval (2.350)
        let initialIntervals = try ConsumptionCalculator.intervals(readings: [r1, r3], meter: gasMeter)
        XCTAssertEqual(initialIntervals.count, 1)
        XCTAssertEqual(initialIntervals[0].amount, Decimal(string: "2.350"))

        // Intermediate insertion: r2 with 101.000
        let r2 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400 * 4), digits: "00101.000", status: .approvedLocal)
        let withIntermediate = try ConsumptionCalculator.intervals(readings: [r1, r2, r3], meter: gasMeter)
        XCTAssertEqual(withIntermediate.count, 2)
        XCTAssertEqual(withIntermediate[0].amount, Decimal(string: "1.000"))
        XCTAssertEqual(withIntermediate[1].amount, Decimal(string: "1.350"))

        // Deletion: removing r2 restores original 2.350 interval
        let afterDeletion = try ConsumptionCalculator.intervals(readings: [r1, r3], meter: gasMeter)
        XCTAssertEqual(afterDeletion.count, 1)
        XCTAssertEqual(afterDeletion[0].amount, Decimal(string: "2.350"))
    }

    func testDecreasingReadingThrowsError() {
        let baseDate = Date(timeIntervalSince1970: 1_770_000_000)
        let r1 = makeReading(meterID: "gas_main", date: baseDate, digits: "00102.350", status: .approvedLocal)
        let r2 = makeReading(meterID: "gas_main", date: baseDate.addingTimeInterval(86400), digits: "00100.000", status: .approvedLocal)

        XCTAssertThrowsError(try ConsumptionCalculator.intervals(readings: [r1, r2], meter: gasMeter)) { error in
            guard case let ConsumptionCalculationError.decreasingValue(from, to, at) = error else {
                XCTFail("Expected decreasingValue error, got \(error)")
                return
            }
            XCTAssertEqual(from, Decimal(string: "102.350"))
            XCTAssertEqual(to, Decimal(string: "100.000"))
            XCTAssertEqual(at, r2.capturedAt)
        }
    }

    func testConflictingTimestampThrowsError() {
        let sameDate = Date(timeIntervalSince1970: 1_770_000_000)
        let r1 = makeReading(meterID: "gas_main", date: sameDate, digits: "00100.000", status: .approvedLocal)
        let r2 = makeReading(meterID: "gas_main", date: sameDate, digits: "00101.000", status: .approvedLocal)

        XCTAssertThrowsError(try ConsumptionCalculator.intervals(readings: [r1, r2], meter: gasMeter)) { error in
            guard case let ConsumptionCalculationError.conflictingTimestamp(date) = error else {
                XCTFail("Expected conflictingTimestamp error, got \(error)")
                return
            }
            XCTAssertEqual(date, sameDate)
        }
    }

    func testDaylightSavingTransitionPreservesOrder() throws {
        // DST transition in Europe: March 29, 2026 at 01:00 UTC -> 02:00 CET becomes 03:00 CEST
        let beforeDST = Date(timeIntervalSince1970: 1_774_745_999) // 2026-03-29 00:59:59 UTC
        let afterDST = Date(timeIntervalSince1970: 1_774_749_601)  // 2026-03-29 02:00:01 UTC

        let r1 = makeReading(meterID: "gas_main", date: beforeDST, digits: "00100.000", status: .approvedLocal)
        let r2 = makeReading(meterID: "gas_main", date: afterDST, digits: "00101.500", status: .approvedLocal)

        let intervals = try ConsumptionCalculator.intervals(readings: [r2, r1], meter: gasMeter) // passed in reverse
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].start, beforeDST)
        XCTAssertEqual(intervals[0].end, afterDST)
        XCTAssertEqual(intervals[0].amount, Decimal(string: "1.500"))
    }

    private func makeReading(
        meterID: String,
        date: Date,
        digits: String?,
        status: ReadingStatus
    ) -> MeterReading {
        MeterReading(
            id: UUID(),
            revision: 0,
            meterID: meterID,
            photoID: UUID(),
            capturedAt: date,
            window: nil,
            proposal: nil,
            approvedDigits: digits,
            status: status,
            modelVersion: nil,
            lastSyncError: nil
        )
    }
}
