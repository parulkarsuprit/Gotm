import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [RecordingEntry] = []

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        load()
    }

    func add(_ entry: RecordingEntry) {
        recordings.insert(entry, at: 0)
        sortByDate()
        save()
    }

    func updateName(for entryID: UUID, name: String) {
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else { return }
        recordings[index].name = name
        recordings[index].isTitleLoading = false
        save()
    }

    func updateTags(for entryID: UUID, tags: [EntryTag]) {
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else { return }
        recordings[index].tags = tags
        save()
    }

    func updateTranscript(for entryID: UUID, transcript: String) {
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else { return }
        recordings[index].transcript = transcript
        save()
    }

    func updateAudioTitle(for entryID: UUID, title: String) {
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else { return }
        recordings[index].audioTitle = title
        save()
    }

    func updateAttachment(for entryID: UUID, attachmentID: UUID, name: String? = nil, transcript: String? = nil) {
        guard let eIdx = recordings.firstIndex(where: { $0.id == entryID }),
              let aIdx = recordings[eIdx].attachments.firstIndex(where: { $0.id == attachmentID })
        else { return }
        if let name { recordings[eIdx].attachments[aIdx].name = name }
        if let transcript { recordings[eIdx].attachments[aIdx].transcript = transcript }
        save()
    }

    func delete(_ entry: RecordingEntry) {
        guard let index = recordings.firstIndex(of: entry) else { return }
        let removed = recordings.remove(at: index)
        // Capture everything needed for background I/O before leaving main actor
        let audioURL = removed.audioURL
        let attachmentURLs = removed.attachments.map { $0.url }
        let saveURL = recordingsFileURL()
        let snapshot = recordings
        // File deletions and save run off the main thread so UI never freezes
        Task.detached(priority: .utility) {
            if let url = audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            for url in attachmentURLs {
                try? FileManager.default.removeItem(at: url)
            }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: saveURL, options: .atomic)
            }
        }
    }

    static func mediaDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "Media", directoryHint: .isDirectory)
    }

    static func saveMedia(_ data: Data, fileExtension ext: String, fileManager: FileManager = .default) throws -> URL {
        let dir = mediaDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: dir.path) {
            // Create with encryption protection
            try fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        let url = dir.appending(path: UUID().uuidString + "." + ext)
        // Write with encryption
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    private func recordingsFileURL() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "recordings.json")
    }

    private func ensureRecordingsDirectoryExists() {
        let directory = Self.recordingsDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: directory.path) {
            // Create with encryption protection
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
    }

    private func load() {
        ensureRecordingsDirectoryExists()
        let url = recordingsFileURL()

        guard let data = try? Data(contentsOf: url) else {
            recordings = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([RecordingEntry].self, from: data)
            let normalized = decoded.map { entry -> RecordingEntry in
                guard entry.duration <= 0, let audioURL = entry.audioURL else { return entry }
                let assetDuration = AVURLAsset(url: audioURL).duration.seconds
                guard assetDuration.isFinite && assetDuration > 0 else { return entry }
                return RecordingEntry(
                    id: entry.id,
                    name: entry.name,
                    isTitleLoading: entry.isTitleLoading,
                    date: entry.date,
                    duration: assetDuration,
                    audioURL: entry.audioURL,
                    audioTitle: entry.audioTitle,
                    transcript: entry.transcript,
                    text: entry.text,
                    attachments: entry.attachments
                )
            }
            recordings = normalized.sorted { $0.date > $1.date }
        } catch {
            recordings = []
        }
    }

    private func save() {
        ensureRecordingsDirectoryExists()
        let url = recordingsFileURL()
        do {
            let data = try JSONEncoder().encode(recordings)
            // Write with encryption - file is encrypted when device is locked
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("❌ [RecordingStore] Save failed: \(error)")
        }
    }

    private func deleteFile(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func sortByDate() {
        recordings.sort { $0.date > $1.date }
    }
}
