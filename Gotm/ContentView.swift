import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Compose Draft Types

private struct DraftAudioItem: Identifiable {
    let id: UUID
    let url: URL
    var duration: TimeInterval
    var transcript: String?
    var isTranscribing: Bool

    init(url: URL, duration: TimeInterval) {
        self.id = UUID()
        self.url = url
        self.duration = duration
        self.transcript = nil
        self.isTranscribing = true
    }
}

private struct DraftAttachment: Identifiable {
    let id: UUID
    let url: URL
    let type: MediaType
    let thumbnail: UIImage?
    let fileName: String

    init(url: URL, type: MediaType, thumbnail: UIImage? = nil) {
        self.id = UUID()
        self.url = url
        self.type = type
        self.thumbnail = thumbnail
        self.fileName = url.deletingPathExtension().lastPathComponent
    }
}

private struct ComposeDraft {
    var text: String = ""
    var audioItems: [DraftAudioItem] = []
    var attachments: [DraftAttachment] = []

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !audioItems.isEmpty ||
        !attachments.isEmpty
    }

    var hasChips: Bool {
        !audioItems.isEmpty || !attachments.isEmpty
    }

    mutating func removeAudioItem(id: UUID) {
        if let idx = audioItems.firstIndex(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: audioItems[idx].url)
            audioItems.remove(at: idx)
        }
    }

    mutating func removeAttachment(id: UUID) {
        if let idx = attachments.firstIndex(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: attachments[idx].url)
            attachments.remove(at: idx)
        }
    }
}

// MARK: - ContentView

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

    @State private var draft = ComposeDraft()
    @State private var pendingTranscriptionEntryID: UUID? = nil
    @State private var pendingAudioItemIDs: Set<UUID> = []

    @FocusState private var isTextFieldFocused: Bool
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showAttachmentMenu = false

    var body: some View {
        let isRecordingUI = isShowingRecordingUI || recordingService.isRecording
        let showChips = draft.hasChips && !isRecordingUI

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

                // Attachment menu panel — floats above bottom bar
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
                VStack(spacing: 8) {
                    // Compose chips strip — appears when draft has audio or attachments
                    if showChips {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draft.audioItems) { item in
                                    DraftChipView(
                                        icon: "waveform",
                                        label: item.isTranscribing ? "Processing…" : formatDuration(item.duration),
                                        isLoading: item.isTranscribing
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            draft.removeAudioItem(id: item.id)
                                        }
                                    }
                                }
                                ForEach(draft.attachments) { attachment in
                                    if attachment.type == .image, let thumb = attachment.thumbnail {
                                        DraftImageChipView(image: thumb) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                draft.removeAttachment(id: attachment.id)
                                            }
                                        }
                                    } else {
                                        DraftChipView(
                                            icon: "doc.fill",
                                            label: attachment.fileName,
                                            isLoading: false
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                draft.removeAttachment(id: attachment.id)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Main capsule bar
                    HStack(alignment: .center, spacing: 10) {
                        // Left slot
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

                        // Center slot
                        if isRecordingUI {
                            RecordingTimerView(elapsedTime: recordingService.elapsedTime)
                                .frame(maxWidth: .infinity)
                        } else {
                            TextField("Write a note...", text: $draft.text, axis: .vertical)
                                .lineLimit(1...4)
                                .focused($isTextFieldFocused)
                                .frame(maxWidth: .infinity)
                                .onSubmit { submitDraft() }

                            if draft.hasContent {
                                Button(action: submitDraft) {
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

                        // Right slot
                        RecordButton(isRecording: isRecordingUI, action: primaryRecordAction, size: 48)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showChips)
                .animation(.easeInOut(duration: 0.18), value: isRecordingUI)
                .animation(.easeInOut(duration: 0.15), value: draft.hasContent)
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
                    Task { await addImageToDraft(image) }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .any(of: [.images, .videos]))
            .onChange(of: photoPickerItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await addImageToDraft(image)
                    }
                    photoPickerItem = nil
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .plainText, .image, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await addFileToDraft(result) }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - List

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

    // MARK: - Recording

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
                if granted { startRecordingWithImmediateUI() } else { showingPermissionAlert = true }
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
        guard let (fileURL, duration) = recordingService.stopRecording() else { return }

        var newItem = DraftAudioItem(url: fileURL, duration: duration)
        let itemID = newItem.id
        draft.audioItems.append(newItem)

        Task {
            do {
                let transcript = try await TranscriptionService.shared.transcribe(fileURL: fileURL)

                if pendingAudioItemIDs.contains(itemID), let entryID = pendingTranscriptionEntryID {
                    // User submitted before this transcription finished
                    if Self.isValidTranscript(transcript) {
                        let entry = store.recordings.first(where: { $0.id == entryID })
                        let isPrimary = entry?.audioURL != nil &&
                            !pendingAudioItemIDs.subtracting([itemID]).isEmpty == false
                            // treat as primary if it's the only/first audio item
                        // Store transcript on the correct slot
                        if entry?.transcript == nil {
                            store.updateTranscript(for: entryID, transcript: transcript)
                        } else {
                            // Additional clip — find the attachment with no transcript yet
                            if let attachment = entry?.audioAttachments.first(where: { $0.transcript == nil }) {
                                store.updateAttachment(for: entryID, attachmentID: attachment.id, transcript: transcript)
                            }
                        }
                        // Generate individual clip title
                        Task {
                            let clipTitle = await TitleService.shared.generateTitle(for: transcript)
                            if entry?.transcript == nil {
                                store.updateAudioTitle(for: entryID, title: clipTitle)
                            } else if let attachment = store.recordings
                                .first(where: { $0.id == entryID })?
                                .audioAttachments.first(where: { $0.name == nil }) {
                                store.updateAttachment(for: entryID, attachmentID: attachment.id, name: clipTitle)
                            }
                        }
                    }
                    pendingAudioItemIDs.remove(itemID)
                    if pendingAudioItemIDs.isEmpty {
                        // All transcriptions done — regenerate entry title
                        if let entry = store.recordings.first(where: { $0.id == entryID }) {
                            let allTranscripts = ([entry.transcript] + entry.audioAttachments.map { $0.transcript })
                                .compactMap { $0 }.filter { !$0.isEmpty }
                            if !allTranscripts.isEmpty {
                                Task {
                                    let title = await TitleService.shared.generateEntryTitle(for: allTranscripts)
                                    store.updateName(for: entryID, name: title)
                                }
                            }
                        }
                        transcribingIDs.remove(entryID)
                        pendingTranscriptionEntryID = nil
                    }
                } else if let idx = draft.audioItems.firstIndex(where: { $0.id == itemID }) {
                    // Still in draft — update transcript or remove if noise
                    if Self.isValidTranscript(transcript) {
                        draft.audioItems[idx].transcript = transcript
                        draft.audioItems[idx].isTranscribing = false
                    } else {
                        print("🚫 [Transcription] Noise/blank — removing audio from draft")
                        try? FileManager.default.removeItem(at: fileURL)
                        draft.audioItems.remove(at: idx)
                    }
                }
            } catch {
                print("❌ [Transcription] Error: \(error.localizedDescription)")
                if !pendingAudioItemIDs.contains(itemID),
                   let idx = draft.audioItems.firstIndex(where: { $0.id == itemID }) {
                    try? FileManager.default.removeItem(at: draft.audioItems[idx].url)
                    draft.audioItems.remove(at: idx)
                }
            }
            // Clear transcribing flag if still in draft
            if let idx = draft.audioItems.firstIndex(where: { $0.id == itemID }) {
                draft.audioItems[idx].isTranscribing = false
            }
        }
    }

    // MARK: - Media

    private func addImageToDraft(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            let url = try RecordingStore.saveMedia(data, fileExtension: "jpg")
            let attachment = DraftAttachment(url: url, type: .image, thumbnail: image)
            draft.attachments.append(attachment)
        } catch {
            print("❌ [Media] Failed to save image: \(error)")
        }
    }

    private func addFileToDraft(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let savedURL = try RecordingStore.saveMedia(data, fileExtension: ext)
            let attachment = DraftAttachment(url: savedURL, type: .file)
            draft.attachments.append(attachment)
        } catch {
            print("❌ [File] Import failed: \(error)")
        }
    }

    // MARK: - Submit

    private func submitDraft() {
        guard draft.hasContent else { return }

        let textContent = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaAttachments = draft.attachments.map {
            MediaAttachment(id: $0.id, url: $0.url, type: $0.type)
        }

        // Primary audio is first item; additional audio clips become .audio attachments
        // Each carries its own transcript (not combined)
        let primaryAudio = draft.audioItems.first
        let additionalAudioItems = Array(draft.audioItems.dropFirst())
        let audioAttachments = additionalAudioItems.map {
            MediaAttachment(id: $0.id, url: $0.url, type: .audio, transcript: $0.transcript)
        }

        // Gather all available transcripts for title generation
        let allTranscripts = draft.audioItems.compactMap { $0.transcript }.filter { !$0.isEmpty }
        let hasTitleSources = !allTranscripts.isEmpty || !textContent.isEmpty
        let inFlightIDs = Set(draft.audioItems.filter { $0.isTranscribing }.map { $0.id })

        let entry = RecordingEntry(
            name: "Loading…",
            isTitleLoading: hasTitleSources || !inFlightIDs.isEmpty,
            duration: primaryAudio?.duration ?? 0,
            audioURL: primaryAudio?.url,
            transcript: primaryAudio?.transcript,
            text: textContent.isEmpty ? nil : textContent,
            attachments: mediaAttachments + audioAttachments
        )
        store.add(entry)

        // Track in-flight transcriptions so they update the saved entry on completion
        if !inFlightIDs.isEmpty {
            pendingTranscriptionEntryID = entry.id
            pendingAudioItemIDs = inFlightIDs
            transcribingIDs.insert(entry.id)
        }

        // Fire all title generation concurrently now if transcriptions are already done
        if inFlightIDs.isEmpty && hasTitleSources {
            let entryID = entry.id
            let titleSources = allTranscripts.isEmpty ? [textContent] : allTranscripts

            // Entry-level title (multi-topic aware)
            Task {
                let title = await TitleService.shared.generateEntryTitle(for: titleSources)
                store.updateName(for: entryID, name: title)
            }
            // Primary clip title
            if let t = primaryAudio?.transcript, !t.isEmpty {
                Task {
                    let clipTitle = await TitleService.shared.generateTitle(for: t)
                    store.updateAudioTitle(for: entryID, title: clipTitle)
                }
            }
            // Additional clip titles
            for (attachment, item) in zip(audioAttachments, additionalAudioItems) {
                if let t = item.transcript, !t.isEmpty {
                    let aid = attachment.id
                    Task {
                        let clipTitle = await TitleService.shared.generateTitle(for: t)
                        store.updateAttachment(for: entryID, attachmentID: aid, name: clipTitle)
                    }
                }
            }
        }

        draft = ComposeDraft()
        isTextFieldFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Helpers

    private static func isValidTranscript(_ text: String) -> Bool {
        var result = ""
        var depth = 0
        for char in text {
            if char == "[" || char == "(" { depth += 1 }
            else if char == "]" || char == ")" { depth -= 1 }
            else if depth == 0 { result.append(char) }
        }
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations: Set<String> = ["you", "thank you", "thanks", "bye", "yes", "no", "okay", "ok", "um", "uh"]
        if hallucinations.contains(cleaned.lowercased().trimmingCharacters(in: .punctuationCharacters)) { return false }
        return cleaned.split(separator: " ").filter { $0.count > 1 }.count >= 2
    }

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func deleteSelected() {
        for entry in store.recordings.filter({ selectedIDs.contains($0.id) }) {
            store.delete(entry)
        }
        selectedIDs.removeAll()
        selectionMode = false
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let t = Int(duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
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

// MARK: - Recording UI

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
        let t = Int(duration.rounded())
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

// MARK: - Compose Chips

private struct DraftChipView: View {
    let icon: String
    let label: String
    let isLoading: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            if !isLoading {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .background(Color(.quaternarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct DraftImageChipView: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.9))
                        .frame(width: 20, height: 20)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - Sheets

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
                    Button("Cancel") { dismiss() }
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

    private var isPlayingMain: Bool {
        recordingService.isPlaying && recordingService.playingURL == entry.audioURL
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Primary audio card with its title + transcript
                    if entry.hasAudio, let audioURL = entry.audioURL {
                        audioCard(
                            url: audioURL,
                            duration: entry.duration,
                            clipTitle: entry.audioTitle,
                            transcript: entry.transcript
                        )
                    }

                    // Additional audio clips — each with their own title + transcript
                    ForEach(Array(entry.audioAttachments.enumerated()), id: \.element.id) { idx, attachment in
                        audioCard(
                            url: attachment.url,
                            duration: nil,
                            clipTitle: attachment.name,
                            transcript: attachment.transcript
                        )
                    }

                    // Image attachments
                    ForEach(entry.imageAttachments) { attachment in
                        if let uiImage = UIImage(contentsOfFile: attachment.url.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // File attachments
                    ForEach(entry.fileAttachments) { attachment in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(attachment.url.lastPathComponent)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Text note
                    if let text = entry.text, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.headline)
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
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

    @ViewBuilder
    private func audioCard(url: URL, duration: TimeInterval?, clipTitle: String?, transcript: String?) -> some View {
        let isThisPlaying = recordingService.isPlaying && recordingService.playingURL == url
        VStack(alignment: .leading, spacing: 12) {
            // Clip title
            if let clipTitle {
                Text(clipTitle)
                    .font(.headline)
            }

            // Playback controls
            HStack(spacing: 14) {
                Button {
                    recordingService.play(url: url)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.label))
                            .frame(width: 44, height: 44)
                        Image(systemName: isThisPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    if isThisPlaying {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemFill)).frame(height: 3)
                                Capsule()
                                    .fill(Color(.label))
                                    .frame(width: geo.size.width * progressFraction(for: url), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    HStack {
                        Text(isThisPlaying
                             ? formatDur(recordingService.playbackProgress)
                             : formatDur(duration ?? 0))
                        Spacer()
                        Text(formatDate(entry.date))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Transcript inline
            if let transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text("No transcription")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func progressFraction(for url: URL) -> CGFloat {
        guard recordingService.isPlaying && recordingService.playingURL == url,
              recordingService.playbackDuration > 0 else { return 0 }
        return CGFloat(min(recordingService.playbackProgress / recordingService.playbackDuration, 1))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDur(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}
