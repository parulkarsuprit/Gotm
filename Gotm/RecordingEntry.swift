import Foundation

enum MediaType: String, Codable {
    case image
    case file
    case audio
}

struct MediaAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let type: MediaType
    var name: String?        // individual title (audio clips)
    var transcript: String?  // individual transcript (audio clips)

    init(id: UUID = UUID(), url: URL, type: MediaType, name: String? = nil, transcript: String? = nil) {
        self.id = id
        self.url = url
        self.type = type
        self.name = name
        self.transcript = transcript
    }
}

struct RecordingEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isTitleLoading: Bool
    let date: Date
    var duration: TimeInterval
    var audioURL: URL?
    var audioTitle: String?   // individual title for primary audio clip
    var transcript: String?   // transcript for primary audio clip only
    var text: String?
    var attachments: [MediaAttachment]
    var tags: [EntryTag]

    var hasAudio: Bool { audioURL != nil }
    var hasText: Bool { !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasMedia: Bool { !attachments.isEmpty }
    var isTextEntry: Bool { !hasAudio && !hasMedia }
    var imageAttachments: [MediaAttachment] { attachments.filter { $0.type == .image } }
    var fileAttachments: [MediaAttachment] { attachments.filter { $0.type == .file } }
    var audioAttachments: [MediaAttachment] { attachments.filter { $0.type == .audio } }
    var totalItemCount: Int { (audioURL != nil ? 1 : 0) + attachments.count + (hasText ? 1 : 0) }

    /// Tags sorted by status (auto first, then suggested) then by feed priority
    var prioritisedTags: [EntryTag] {
        tags.sorted {
            // First sort by status: auto (high confidence) comes before suggested
            let statusOrder: [TagStatus] = [.auto, .suggested]
            let firstStatusIndex = statusOrder.firstIndex(of: $0.status) ?? 0
            let secondStatusIndex = statusOrder.firstIndex(of: $1.status) ?? 0
            
            if firstStatusIndex != secondStatusIndex {
                return firstStatusIndex < secondStatusIndex
            }
            
            // Then sort by feed priority
            return $0.type.feedPriority < $1.type.feedPriority
        }
    }

    init(id: UUID = UUID(), name: String, isTitleLoading: Bool = false, date: Date = Date(),
         duration: TimeInterval = 0, audioURL: URL? = nil, audioTitle: String? = nil,
         transcript: String? = nil, text: String? = nil, attachments: [MediaAttachment] = [],
         tags: [EntryTag] = []) {
        self.id = id
        self.name = name
        self.isTitleLoading = isTitleLoading
        self.date = date
        self.duration = duration
        self.audioURL = audioURL
        self.audioTitle = audioTitle
        self.transcript = transcript
        self.text = text
        self.attachments = attachments
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isTitleLoading, date, duration, audioURL, audioTitle, transcript, text, attachments, tags
        case legacyFileURL = "fileURL"
        case legacyMediaURL = "mediaURL"
        case legacyMediaType = "mediaType"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isTitleLoading = try c.decodeIfPresent(Bool.self, forKey: .isTitleLoading) ?? false
        date = try c.decode(Date.self, forKey: .date)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        audioURL = try c.decodeIfPresent(URL.self, forKey: .audioURL)
            ?? c.decodeIfPresent(URL.self, forKey: .legacyFileURL)
        audioTitle = try c.decodeIfPresent(String.self, forKey: .audioTitle)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        var decoded = try c.decodeIfPresent([MediaAttachment].self, forKey: .attachments) ?? []
        if decoded.isEmpty,
           let oldURL = try c.decodeIfPresent(URL.self, forKey: .legacyMediaURL),
           let oldType = try c.decodeIfPresent(MediaType.self, forKey: .legacyMediaType) {
            decoded = [MediaAttachment(id: UUID(), url: oldURL, type: oldType)]
        }
        attachments = decoded
        tags = try c.decodeIfPresent([EntryTag].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isTitleLoading, forKey: .isTitleLoading)
        try c.encode(date, forKey: .date)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(audioURL, forKey: .audioURL)
        try c.encodeIfPresent(audioTitle, forKey: .audioTitle)
        try c.encodeIfPresent(transcript, forKey: .transcript)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(tags, forKey: .tags)
    }
}
