import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case needsReview
    case positionIdentified
    case counterRecognized
    case pendingSync
    case synced
    case approvedLocal
}

struct NormalizedRect: Codable, Equatable, Sendable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    var width: Double {
        max(0.0, right - left)
    }

    var height: Double {
        max(0.0, bottom - top)
    }

    var centerX: Double {
        (left + right) / 2.0
    }

    var centerY: Double {
        (top + bottom) / 2.0
    }

    var aspectRatio: Double {
        guard height > 0.0001 else { return 0.0 }
        return width / height
    }

    func scaled(by scale: Double, minWidth: Double = 0.005, minHeight: Double = 0.0005) -> NormalizedRect {
        let currentW = width
        let currentH = height
        let newW = max(minWidth, currentW * scale)
        let newH = max(minHeight, currentH * scale)
        let cx = centerX
        let cy = centerY

        var newLeft = cx - newW / 2.0
        var newRight = cx + newW / 2.0
        var newTop = cy - newH / 2.0
        var newBottom = cy + newH / 2.0

        if newLeft < 0.0 {
            newRight += -newLeft
            newLeft = 0.0
        }
        if newRight > 1.0 {
            newLeft -= (newRight - 1.0)
            newRight = 1.0
        }
        if newTop < 0.0 {
            newBottom += -newTop
            newTop = 0.0
        }
        if newBottom > 1.0 {
            newTop -= (newBottom - 1.0)
            newBottom = 1.0
        }

        return NormalizedRect(
            left: max(0.0, newLeft),
            top: max(0.0, newTop),
            right: min(1.0, max(newLeft + minWidth, newRight)),
            bottom: min(1.0, max(newTop + minHeight, newBottom))
        )
    }
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
