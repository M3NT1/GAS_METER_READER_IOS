import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case needsReview
    case positionIdentified
    case counterRecognized
    case pendingSync
    case synced
}

struct NormalizedRect: Codable, Equatable, Sendable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
}

struct DigitProposal: Codable, Equatable, Sendable {
    let digits: String
    let confidences: [Double]
    let uncertainPositions: [Int]
}

struct MeterReading: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var revision: Int
    let meterID: String
    let photoID: UUID
    let capturedAt: Date
    var window: NormalizedRect?
    var proposal: DigitProposal?
    var approvedDigits: String?
    var status: ReadingStatus
    var modelVersion: String?
    var lastSyncError: String?
}

struct ApprovedReadingValue: Equatable, Sendable {
    let displayValue: String
    let uploadValue: String
}
