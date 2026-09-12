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

    func testProposeReportsInferenceProgressPhases() async throws {
        let window = NormalizedRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.3)
        let service = InferenceService(runtime: FakeRuntime(
            detector: [DetectorCandidate(window: window, confidence: 0.95)],
            classifier: (0..<8).map { ClassifierOutput(digit: $0, confidence: 0.99) }
        ))

        let recorder = ProgressRecorder()
        let result = try await service.propose(
            imageURL: URL(fileURLWithPath: "/meter.jpg"),
            manualWindow: nil,
            onProgress: { progress in
                recorder.record(progress)
            }
        )

        XCTAssertEqual(result.proposal?.digits, "01234567")
        XCTAssertEqual(recorder.recorded, [
            .detectingWindow,
            .classifyingDigits(window: window)
        ])
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [InferenceProgress] = []

    func record(_ progress: InferenceProgress) {
        lock.lock()
        defer { lock.unlock() }
        items.append(progress)
    }

    var recorded: [InferenceProgress] {
        lock.lock()
        defer { lock.unlock() }
        return items
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
