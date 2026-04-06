import Observation
import SwiftUI

@MainActor
@Observable
final class FeedViewModel {
    // MARK: - State
    var selectionMode = false
    var selectedIDs: Set<UUID> = []
    var transcribingIDs: Set<UUID> = []
    var showSearch = false
    var searchText = ""
    var editingEntry: RecordingEntry?
    var viewingEntry: RecordingEntry?

    // MARK: - Actions
    var onDelete: ((Set<UUID>) -> Void)?

    var isSearching: Bool {
        !searchText.isEmpty
    }

    // MARK: - Selection

    func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll(from entries: [RecordingEntry]) {
        selectedIDs = Set(entries.map { $0.id })
    }

    func clearSelection() {
        selectionMode = false
        selectedIDs.removeAll()
    }

    func deleteSelected() {
        onDelete?(selectedIDs)
        clearSelection()
    }

    // MARK: - Search

    func filteredRecordings(from recordings: [RecordingEntry]) -> [RecordingEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recordings }
        return recordings.filter { entry in
            entry.name.lowercased().contains(query) ||
            (entry.transcript?.lowercased().contains(query) ?? false) ||
            (entry.text?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Transcription Status

    func setTranscribing(_ entryID: UUID, _ isTranscribing: Bool) {
        if isTranscribing {
            transcribingIDs.insert(entryID)
        } else {
            transcribingIDs.remove(entryID)
        }
    }
}
