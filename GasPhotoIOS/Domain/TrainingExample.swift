import Foundation

enum TrainingDecision: String, Codable, Equatable, Sendable {
    case approved
    case corrected
}

struct TrainingExample: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let readingID: UUID
    let photoID: UUID
    let window: NormalizedRect
    var digits: String
    var decision: TrainingDecision
    let createdAt: Date

    init(
        id: UUID = UUID(),
        readingID: UUID,
        photoID: UUID,
        window: NormalizedRect,
        digits: String,
        decision: TrainingDecision,
        createdAt: Date
    ) {
        self.id = id
        self.readingID = readingID
        self.photoID = photoID
        self.window = window
        self.digits = digits
        self.decision = decision
        self.createdAt = createdAt
    }
}
