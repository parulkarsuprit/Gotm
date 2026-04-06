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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if recordings.isEmpty {
                            Text("No notes match \(viewModel.searchText)")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
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
                                .swipeToDelete { onDeleteEntry(entry) }
                                .contentShape(Rectangle())
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
                    .padding(.vertical, 6)
                }
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

        // Avoid repeating recent colors
        let recentIndices = (0..<min(index, 2)).map { idx in
            recordings[max(0, index - idx - 1)].id.hashValue
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
