import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var store = RecordingStore()
    @State private var recordingService = RecordingService.shared

    @State private var showingPermissionAlert = false
    @State private var editingEntry: RecordingEntry?
    @State private var isShowingRecordingUI = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        let isRecordingUI = isShowingRecordingUI || recordingService.isRecording

        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.99),
                        Color(red: 0.95, green: 0.96, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isRecordingUI {
                    RecordingView(level: recordingService.recordingLevel)
                } else {
                    recordingsListView
                }
            }
            .navigationTitle(isRecordingUI ? "" : "Gotm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isRecordingUI {
                    ToolbarItem(placement: .principal) {
                        RecordingTimerView(elapsedTime: recordingService.elapsedTime)
                    }
                }

                if selectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            selectionMode = false
                            selectedIDs.removeAll()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button("Select All") {
                                selectedIDs = Set(store.recordings.map { $0.id })
                            }

                            Button(role: .destructive) {
                                deleteSelected()
                            } label: {
                                Text("Delete")
                            }
                            .disabled(selectedIDs.isEmpty)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                RecordButton(isRecording: isRecordingUI, action: primaryRecordAction)
                    .padding(.vertical, 12)
            }
            .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable microphone access in Settings to record voice memos.")
            }
            .sheet(item: $editingEntry) { entry in
                RenameRecordingSheet(entry: entry) { newName in
                    store.updateName(for: entry.id, name: newName)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var recordingsListView: some View {
        VStack(spacing: 0) {
            if store.recordings.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(store.recordings) { entry in
                        RecordingRowView(
                            entry: entry,
                            isPlaying: recordingService.isPlaying && recordingService.playingURL == entry.fileURL,
                            playbackProgress: recordingService.playbackProgress,
                            playbackDuration: recordingService.playbackDuration,
                            isSelectable: selectionMode,
                            isSelected: selectedIDs.contains(entry.id),
                            playAction: { recordingService.play(url: entry.fileURL) }
                        )
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onTapGesture {
                            if selectionMode {
                                toggleSelection(for: entry.id)
                            } else {
                                editingEntry = entry
                            }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button {
                                store.delete(entry)
                            } label: {
                                Image(systemName: "trash")
                                    .accessibilityLabel("Delete")
                            }
                            .tint(.red)
                        }
                        .onLongPressGesture(minimumDuration: 0.25) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectionMode = true
                            toggleSelection(for: entry.id)
                        }
                                            }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyStateView: some View {
        Text("whats on your mind, supr?")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primaryRecordAction() {
        if recordingService.isRecording || isShowingRecordingUI {
            stopRecording()
            return
        }

        Task {
            let permission = AVAudioSession.sharedInstance().recordPermission
            switch permission {
            case .undetermined:
                let granted = await recordingService.requestPermission()
                if granted {
                    startRecordingWithImmediateUI()
                } else {
                    showingPermissionAlert = true
                }
            case .denied:
                showingPermissionAlert = true
            case .granted:
                startRecordingWithImmediateUI()
            @unknown default:
                showingPermissionAlert = true
            }
        }
    }

    private func startRecordingWithImmediateUI() {
        isShowingRecordingUI = true

        Task { @MainActor in
            await Task.yield()
            do {
                try recordingService.startRecording()
                isShowingRecordingUI = false
            } catch {
                isShowingRecordingUI = false
                showingPermissionAlert = true
            }
        }
    }

    private func stopRecording() {
        isShowingRecordingUI = false
        if let entry = recordingService.stopRecording() {
            store.add(entry)
        }
    }

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let entries = store.recordings.filter { selectedIDs.contains($0.id) }
        for entry in entries {
            store.delete(entry)
        }
        selectedIDs.removeAll()
        selectionMode = false
    }
}


private struct RecordingTimerView: View {
    let elapsedTime: TimeInterval

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .shadow(color: Color.red.opacity(0.45), radius: 8)
                .scaleEffect(isPulsing ? 1.5 : 0.8)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)

            Text(formattedElapsedTime(elapsedTime))
                .font(.body)
                .monospacedDigit()
        }
        .onAppear {
            isPulsing = true
        }
    }

    private func formattedElapsedTime(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct RenameRecordingSheet: View {
    let entry: RecordingEntry
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(entry: RecordingEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _name = State(initialValue: entry.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle("Rename")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? entry.name : trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}

