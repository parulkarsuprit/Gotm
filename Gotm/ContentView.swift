import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var textInput: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showAttachmentMenu = false

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
                .onTapGesture { isTextFieldFocused = false }

                if isRecordingUI {
                    RecordingView(level: recordingService.recordingLevel)
                } else {
                    recordingsListView
                }

                // Attachment menu panel — floats above bottom bar, never overlaps it
                if showAttachmentMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) { showAttachmentMenu = false }
                        }

                    VStack(alignment: .leading, spacing: 0) {
                        attachmentMenuButton("Photos & Videos", icon: "photo.on.rectangle") {
                            showPhotoPicker = true
                        }
                        Divider().padding(.leading, 48)
                        attachmentMenuButton("Files & Documents", icon: "folder") {
                            showFileImporter = true
                        }
                        Divider().padding(.leading, 48)
                        attachmentMenuButton("Camera", icon: "camera") {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCamera = true
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(width: 230)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    .padding(.bottom, 2)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .navigationTitle("Gotm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

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
                HStack(alignment: .center, spacing: 10) {
                    // Left slot: + button (normal) or pulsing red dot (recording)
                    if isRecordingUI {
                        RecordingDotView()
                            .frame(width: 32, height: 32)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                showAttachmentMenu.toggle()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color(.label))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Center slot: timer (recording) or text field (normal)
                    if isRecordingUI {
                        RecordingTimerView(elapsedTime: recordingService.elapsedTime)
                            .frame(maxWidth: .infinity)
                    } else {
                        TextField("Write a note...", text: $textInput, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($isTextFieldFocused)
                            .frame(maxWidth: .infinity)
                            .onSubmit { submitTextEntry() }

                        if !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: submitTextEntry) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(.label))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }

                    // Right slot: record button always
                    RecordButton(isRecording: isRecordingUI, action: primaryRecordAction, size: 48)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.18), value: isRecordingUI)
                .animation(.easeInOut(duration: 0.15), value: textInput.isEmpty)
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
            .sheet(isPresented: $showCamera) {
                CameraPickerView { image in
                    Task { await saveImageEntry(image) }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .any(of: [.images, .videos]))
            .onChange(of: photoPickerItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await saveImageEntry(image)
                    }
                    photoPickerItem = nil
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .plainText, .image, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
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
                            index: store.recordings.count - index,
                            isSelectable: selectionMode,
                            isSelected: selectedIDs.contains(entry.id),
                            isTranscribing: transcribingIDs.contains(entry.id)
                        )
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onTapGesture {
                            if isTextFieldFocused {
                                isTextFieldFocused = false
                            } else if selectionMode {
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
                .scrollDismissesKeyboard(.immediately)
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
        showAttachmentMenu = false
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

    private func saveImageEntry(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            let url = try RecordingStore.saveMedia(data, fileExtension: "jpg")
            let entry = RecordingEntry(id: UUID(), name: "Photo", date: Date(), duration: 0, fileURL: nil, transcript: nil, mediaURL: url, mediaType: .image)
            store.add(entry)
        } catch {
            print("❌ [Media] Failed to save image: \(error)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let savedURL = try RecordingStore.saveMedia(data, fileExtension: ext)
            let name = url.deletingPathExtension().lastPathComponent
            let entry = RecordingEntry(id: UUID(), name: name, date: Date(), duration: 0, fileURL: nil, transcript: nil, mediaURL: savedURL, mediaType: .file)
            store.add(entry)
        } catch {
            print("❌ [File] Import failed: \(error)")
        }
    }

    private func submitTextEntry() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        textInput = ""
        isTextFieldFocused = false

        let entry = RecordingEntry(id: UUID(), name: "Note", date: Date(), duration: 0, fileURL: nil, transcript: text)
        store.add(entry)

        Task {
            let title = await TitleService.shared.generateTitle(for: text)
            store.updateName(for: entry.id, name: title)
        }
    }

    private func stopRecording() {
        isShowingRecordingUI = false
        if let entry = recordingService.stopRecording() {
            store.add(entry)
            transcribingIDs.insert(entry.id)
            Task {
                do {
                    guard let fileURL = entry.fileURL else {
                        store.delete(entry)
                        transcribingIDs.remove(entry.id)
                        return
                    }
                    let transcript = try await TranscriptionService.shared.transcribe(fileURL: fileURL)
                    guard Self.isValidTranscript(transcript) else {
                        print("🚫 [Transcription] Discarded — noise or no speech: \(transcript.prefix(60))")
                        store.delete(entry)
                        transcribingIDs.remove(entry.id)
                        return
                    }
                    store.updateTranscript(for: entry.id, transcript: transcript)
                    let title = await TitleService.shared.generateTitle(for: transcript)
                    store.updateName(for: entry.id, name: title)
                } catch {
                    print("❌ [Transcription] Error: \(error.localizedDescription)")
                    store.delete(entry)
                }
                transcribingIDs.remove(entry.id)
            }
        }
    }

    private static func isValidTranscript(_ text: String) -> Bool {
        var cleaned = text

        // Strip WhisperKit noise annotations: [Music], (wind), [BLANK_AUDIO], etc.
        var result = ""
        var depth = 0
        for char in cleaned {
            if char == "[" || char == "(" { depth += 1 }
            else if char == "]" || char == ")" { depth -= 1 }
            else if depth == 0 { result.append(char) }
        }
        cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Known single-word hallucinations WhisperKit produces on silence
        let hallucinations: Set<String> = ["you", "thank you", "thanks", "bye", "yes", "no", "okay", "ok", "um", "uh"]
        let lower = cleaned.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if hallucinations.contains(lower) { return false }

        // Require at least 2 words with more than 1 character each
        let words = cleaned.split(separator: " ").filter { $0.count > 1 }
        return words.count >= 2
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

    @ViewBuilder
    private func attachmentMenuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showAttachmentMenu = false }
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


private struct RecordingDotView: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .shadow(color: Color.red.opacity(0.5), radius: isPulsing ? 8 : 3)
            .scaleEffect(isPulsing ? 1.4 : 0.9)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct RecordingTimerView: View {
    let elapsedTime: TimeInterval

    var body: some View {
        Text(formattedElapsedTime(elapsedTime))
            .font(.body)
            .monospacedDigit()
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
                    // Playback control (audio entries only)
                    if !entry.isTextEntry, let fileURL = entry.fileURL {
                        VStack(spacing: 12) {
                            Button {
                                recordingService.play(url: fileURL)
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
                    }

                    // Media attachment
                    if let mediaURL = entry.mediaURL {
                        if entry.mediaType == .image, let uiImage = UIImage(contentsOfFile: mediaURL.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else if entry.mediaType == .file {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(mediaURL.lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // Full transcription
                    if let transcript = entry.transcript, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.isAudioEntry ? "Transcription" : "Note")
                                .font(.headline)
                            Text(transcript)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    } else if entry.isAudioEntry {
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

