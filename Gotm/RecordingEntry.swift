import Foundation

enum MediaType: String, Codable {
    case image
    case file
}

struct RecordingEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let date: Date
    let duration: TimeInterval
    let fileURL: URL?
    var transcript: String?
    var mediaURL: URL?
    var mediaType: MediaType?

    var isTextEntry: Bool { fileURL == nil && mediaURL == nil }
    var isAudioEntry: Bool { fileURL != nil }
    var isMediaEntry: Bool { mediaURL != nil }
}
