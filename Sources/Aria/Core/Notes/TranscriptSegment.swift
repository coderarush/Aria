import Foundation

struct TranscriptSegment: Codable, Sendable, Equatable {
    var speakerLabel: String   // "Turn 1", "Turn 2", etc.
    var text: String
    var timestamp: Date
}
