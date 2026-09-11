import XCTest
@testable import GasPhotoIOS

final class InferenceServiceTests: XCTestCase {
    func testMultipleDetectorCandidatesRequireManualWindow() async throws {
        let first = NormalizedRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3)
        let second = NormalizedRect(left: 0.4, top: 0.5, right: 0.8, bottom: 0.6)
        let service = InferenceService(runtime: FakeRuntime(
            detector: [
                DetectorCandidate(window: first, confidence: 0.9),
                DetectorCandidate(window: second, confidence: 0.8)
            ],
            classifier: []
        ))

        let result = try await service.propose(imageURL: URL(fileURLWithPath: "/meter.jpg"), manualWindow: nil)

        XCTAssertNil(result.window)
        XCTAssertNil(result.proposal)
    }

    func testLowConfidenceBlackRollerIsMarkedUncertain() async throws {
        let window = NormalizedRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.3)
        let service = InferenceService(runtime: FakeRuntime(
            detector: [DetectorCandidate(window: window, confidence: 0.9)],
            classifier: [
                ClassifierOutput(digit: 0, confidence: 0.99),
                ClassifierOutput(digit: 1, confidence: 0.99),
                ClassifierOutput(digit: 8, confidence: 0.74),
                ClassifierOutput(digit: 1, confidence: 0.99),
                ClassifierOutput(digit: 7, confidence: 0.99),
                ClassifierOutput(digit: 7, confidence: 0.60),
                ClassifierOutput(digit: 5, confidence: 0.99),
                ClassifierOutput(digit: 9, confidence: 0.99)
            ]
        ))

        let result = try await service.propose(imageURL: URL(fileURLWithPath: "/meter.jpg"), manualWindow: nil)

        XCTAssertEqual(result.proposal?.digits, "01817759")
        XCTAssertEqual(result.proposal?.uncertainPositions, [2])
        XCTAssertEqual(result.decimalReviewPositions, [5])
    }
}

private actor FakeRuntime: InferenceRuntime {
    private let detector: [DetectorCandidate]
    private let classifier: [ClassifierOutput]

    init(detector: [DetectorCandidate], classifier: [ClassifierOutput]) {
        self.detector = detector
        self.classifier = classifier
    }

    func detectorCandidates(imageURL: URL) async throws -> [DetectorCandidate] {
        detector
    }

    func classifyRollers(imageURL: URL, window: NormalizedRect) async throws -> [ClassifierOutput] {
        classifier
    }
}
