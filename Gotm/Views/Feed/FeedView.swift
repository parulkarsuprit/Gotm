import SwiftUI

struct FeedView: View {
    @Bindable var viewModel: FeedViewModel
    let store: RecordingStore
    let onTapEntry: (RecordingEntry) -> Void
    let onDeleteEntry: (RecordingEntry) -> Void

    private var recordings: [RecordingEntry] {
        viewModel.filteredRecordings(from: store.recordings)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.recordings.isEmpty {
                EmptyStateView()
            } else {
                List {
                    if recordings.isEmpty {
                        Text("No notes match \(viewModel.searchText)")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(Array(recordings.enumerated()), id: \.element.id) { index, entry in
                            RecordingCard(
                                entry: entry,
                                index: recordings.count - index,
                                isSelectable: viewModel.selectionMode,
                                isSelected: viewModel.selectedIDs.contains(entry.id),
                                isTranscribing: viewModel.transcribingIDs.contains(entry.id),
                                backgroundColor: cardColor(for: entry, at: index)
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDeleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onTapGesture {
                                onTapEntry(entry)
                            }
                            .onLongPressGesture(minimumDuration: 0.25) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.selectionMode = true
                                viewModel.toggleSelection(for: entry.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private func cardColor(for entry: RecordingEntry, at index: Int) -> Color {
        let cardPalette: [Color] = [
            Color(red: 0.99, green: 0.98, blue: 0.96),
            Color(red: 0.99, green: 0.97, blue: 0.97),
            Color(red: 0.99, green: 0.97, blue: 0.94),
            Color(red: 0.96, green: 0.96, blue: 0.96),
            Color(red: 0.99, green: 0.98, blue: 0.94),
            Color(red: 0.97, green: 0.98, blue: 0.97),
        ]

        // Guard: if no recordings or invalid index, return default
        guard !recordings.isEmpty, index >= 0, index < recordings.count else {
            return cardPalette[abs(entry.id.hashValue) % cardPalette.count]
        }

        // Avoid repeating recent colors
        let recentIndices = (0..<min(index, 2)).compactMap { idx -> Int? in
            let targetIndex = max(0, index - idx - 1)
            guard targetIndex < recordings.count else { return nil }
            return recordings[targetIndex].id.hashValue
        }
        let recentColors = recentIndices.map { idx in
            cardPalette[abs(idx) % cardPalette.count]
        }

        let available = cardPalette.filter { c in
            !recentColors.contains(where: { $0 == c })
        }
        let pool = available.isEmpty ? cardPalette : available
        let idx = abs(entry.id.hashValue) % pool.count
        return pool[idx]
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        Text("whats on your mind, supr?")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
