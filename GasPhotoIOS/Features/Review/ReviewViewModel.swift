import Foundation
import Observation

@MainActor
@Observable
final class ReviewViewModel {
    private let repository: any ReadingRepository
    private(set) var reading: MeterReading
    private(set) var lastError: String?

    var status: ReadingStatus { reading.status }

    init(reading: MeterReading, repository: any ReadingRepository) {
        self.reading = reading
        self.repository = repository
    }

    func canApprove(displayDigits: String) -> Bool {
        (try? ReadingValidator.approvedDigits(displayDigits)) != nil
    }

    func approve(displayDigits: String) async {
        do {
            let approved = try ReadingValidator.approvedDigits(displayDigits)
            var updated = reading
            updated.approvedDigits = approved.displayValue
            updated.status = .pendingSync
            try await repository.insert(updated)
            reading = updated
            lastError = nil
        } catch {
            lastError = "A megadott érték nem jóváhagyható."
        }
    }
}
