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
        Task {
            await load()
        }
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
        deleteMultiple([entry])
    }
    
    /// Delete multiple entries efficiently with single background task
    func deleteMultiple(_ entries: [RecordingEntry]) {
        let idsToDelete = Set(entries.map { $0.id })
        
        // Collect all URLs to delete before modifying array
        var urlsToDelete: [URL] = []
        
        // Filter out entries to delete and collect their file URLs
        let entriesToRemove = recordings.filter { idsToDelete.contains($0.id) }
        recordings.removeAll { idsToDelete.contains($0.id) }
        
        for entry in entriesToRemove {
            if let audioURL = entry.audioURL {
                urlsToDelete.append(audioURL)
            }
            urlsToDelete.append(contentsOf: entry.attachments.map { $0.url })
        }
        
        // Save immediately on main thread (data is small)
        save()
        
        // Background task for file cleanup only
        Task.detached(priority: .utility) {
            for url in urlsToDelete {
                try? FileManager.default.removeItem(at: url)
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

    private func load() async {
        ensureRecordingsDirectoryExists()
        let url = recordingsFileURL()

        guard let data = try? Data(contentsOf: url) else {
            recordings = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([RecordingEntry].self, from: data)
            var normalized: [RecordingEntry] = []
            for entry in decoded {
                guard entry.duration <= 0, let audioURL = entry.audioURL else {
                    normalized.append(entry)
                    continue
                }
                // Use async loading for iOS 16+ compatibility
                let asset = AVURLAsset(url: audioURL)
                let duration = try? await asset.load(.duration).seconds
                guard let duration = duration, duration.isFinite && duration > 0 else {
                    normalized.append(entry)
                    continue
                }
                normalized.append(RecordingEntry(
                    id: entry.id,
                    name: entry.name,
                    isTitleLoading: entry.isTitleLoading,
                    date: entry.date,
                    duration: duration,
                    audioURL: entry.audioURL,
                    audioTitle: entry.audioTitle,
                    transcript: entry.transcript,
                    text: entry.text,
                    attachments: entry.attachments
                ))
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
