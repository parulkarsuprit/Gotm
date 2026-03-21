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
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        recordings[index].name = name
        save()
    }

    func updateTranscript(for entryID: UUID, transcript: String) {
        guard let index = recordings.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        recordings[index].transcript = transcript
        
        // Auto-generate name from first 5 words of transcript
        let words = transcript.split(separator: " ").prefix(5)
        if words.count > 0 {
            let generatedName = words.joined(separator: " ") + (words.count >= 5 ? "..." : "")
            recordings[index].name = generatedName
        }
        
        save()
    }

    func delete(_ entry: RecordingEntry) {
        guard let index = recordings.firstIndex(of: entry) else {
            return
        }

        let removed = recordings.remove(at: index)
        if let url = removed.fileURL { deleteFile(at: url) }
        if let url = removed.mediaURL { deleteFile(at: url) }
        save()
    }

    static func mediaDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "Media", directoryHint: .isDirectory)
    }

    static func saveMedia(_ data: Data, fileExtension ext: String, fileManager: FileManager = .default) throws -> URL {
        let dir = mediaDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appending(path: UUID().uuidString + "." + ext)
        try data.write(to: url, options: .atomic)
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
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
            let normalized = decoded.map { entry in
                guard entry.duration <= 0, let url = entry.fileURL else { return entry }
                let assetDuration = AVURLAsset(url: url).duration.seconds
                if assetDuration.isFinite && assetDuration > 0 {
                    return RecordingEntry(
                        id: entry.id,
                        name: entry.name,
                        date: entry.date,
                        duration: assetDuration,
                        fileURL: entry.fileURL,
                        transcript: entry.transcript
                    )
                }
                return entry
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
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private func deleteFile(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    private func sortByDate() {
        recordings.sort { $0.date > $1.date }
    }
}
