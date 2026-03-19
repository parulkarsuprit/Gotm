import Foundation

struct RecordingEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let date: Date
    let duration: TimeInterval
    let fileURL: URL
}
