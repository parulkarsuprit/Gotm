import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var store = RecordingStore()
    @State private var recordingService = RecordingService.shared

    @State private var showingPermissionAlert = false
    @State private var editingEntry: RecordingEntry?
    @State private var viewingEntry: RecordingEntry?
    @State private var isShowingRecordingUI = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var transcribingIDs: Set<UUID> = []

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
                        Button {
                            selectionMode = false
                            selectedIDs.removeAll()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                selectedIDs = Set(store.recordings.map { $0.id })
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 16))
                            }

                            Button(role: .destructive) {
                                deleteSelected()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
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
            .sheet(item: $viewingEntry) { entry in
                RecordingDetailSheet(entry: entry)
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
                    ForEach(Array(store.recordings.enumerated()), id: \.element.id) { index, entry in
                        RecordingRowView(
                            entry: entry,
                            index: index + 1,
                            isSelectable: selectionMode,
                            isSelected: selectedIDs.contains(entry.id),
                            isTranscribing: transcribingIDs.contains(entry.id)
                        )
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onTapGesture {
                            if selectionMode {
                                toggleSelection(for: entry.id)
                            } else {
                                viewingEntry = entry
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
                            
                            Button {
                                editingEntry = entry
                            } label: {
                                Image(systemName: "pencil")
                                    .accessibilityLabel("Rename")
                            }
                            .tint(.blue)
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
            transcribingIDs.insert(entry.id)
            Task {
                do {
                    print("🎤 [Transcription] Starting transcription for: \(entry.fileURL.lastPathComponent)")
                    let transcript = try await TranscriptionService.shared.transcribe(fileURL: entry.fileURL)
                    print("✅ [Transcription] Success! Text: \(transcript.prefix(100))...")
                    store.updateTranscript(for: entry.id, transcript: transcript)
                    let title = await TitleService.shared.generateTitle(for: transcript)
                    store.updateName(for: entry.id, name: title)
                    print("💾 [Transcription] Updated store with transcript and title: \(title)")
                } catch {
                    print("❌ [Transcription] Error: \(error)")
                    print("❌ [Transcription] Error details: \(error.localizedDescription)")
                }
                transcribingIDs.remove(entry.id)
            }
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


private struct RecordingDetailSheet: View {
    let entry: RecordingEntry

    @Environment(\.dismiss) private var dismiss
    @State private var recordingService = RecordingService.shared

    private var isPlaying: Bool {
        recordingService.isPlaying && recordingService.playingURL == entry.fileURL
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Playback control
                    VStack(spacing: 12) {
                        Button {
                            recordingService.play(url: entry.fileURL)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(.label))
                                    .frame(width: 56, height: 56)
                                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color(.systemBackground))
                                    .offset(x: isPlaying ? 0 : 2)
                            }
                        }
                        .buttonStyle(.plain)

                        if isPlaying {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemFill))
                                        .frame(height: 3)
                                    Capsule()
                                        .fill(Color(.label))
                                        .frame(width: geo.size.width * progressFraction, height: 3)
                                }
                            }
                            .frame(height: 3)
                        }

                        HStack {
                            Text(isPlaying ? formattedDuration(recordingService.playbackProgress) : formattedDuration(entry.duration))
                            Spacer()
                            Text(formattedDate(entry.date))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Full transcription
                    if let transcript = entry.transcript, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcription")
                                .font(.headline)
                            Text(transcript)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Transcription",
                            systemImage: "text.bubble",
                            description: Text("This recording hasn't been transcribed yet.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        recordingService.stopPlayback()
                        dismiss()
                    }
                }
            }
        }
    }

    private var progressFraction: CGFloat {
        guard recordingService.playbackDuration > 0 else { return 0 }
        return CGFloat(min(recordingService.playbackProgress / recordingService.playbackDuration, 1))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

