import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {
    // MARK: - Dependencies
    @State private var store = RecordingStore()
    @State private var composeVM = ComposeViewModel()
    @State private var feedVM = FeedViewModel()
    @State private var recordingService = RecordingService.shared

    // MARK: - Local State
    @State private var isShowingRecordingUI = false
    @State private var showingPermissionAlert = false
    @State private var showingRecordingWarning = false
    @State private var recordingDurationAtWarning: TimeInterval = 0
    @State private var recordingCheckTimer: Timer?
    @State private var recordingForEntryID: UUID?
    @State private var recordingItemID: UUID?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        let isNormalRecording = (isShowingRecordingUI || recordingService.isRecording) && composeVM.quickRecordState == .idle
        let showChips = composeVM.draft.hasChips && !isNormalRecording && composeVM.quickRecordState == .idle

        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()
                    .onTapGesture { isTextFieldFocused = false }

                // Main content
                if isNormalRecording {
                    RecordingOverlay(level: composeVM.recordingLevel)
                } else {
                    FeedView(
                        viewModel: feedVM,
                        store: store,
                        onTapEntry: handleEntryTap,
                        onDeleteEntry: { store.delete($0) }
                    )
                }

                // Attachment menu
                if composeVM.showAttachmentMenu {
                    AttachmentMenuView(viewModel: composeVM) {
                        composeVM.showAttachmentMenu = false
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if feedVM.selectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            feedVM.clearSelection()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        selectionToolbar
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                FeedHeader(viewModel: feedVM)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    .background(headerBackground)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar(showChips: showChips, isNormalRecording: isNormalRecording)
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
            .alert("Long Recording", isPresented: $showingRecordingWarning) {
                Button("Stop Recording", role: .destructive) {
                    handleQuickRecordStop()
                }
                Button("Continue") {
                    composeVM.continueRecording()
                    startRecordingCheckTimer()
                }
            } message: {
                let minutes = Int(recordingDurationAtWarning / 60)
                Text("You've been recording for \(minutes) minutes. Continue?")
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $feedVM.editingEntry) { entry in
                RenameSheet(entry: entry) { newName in
                    store.updateName(for: entry.id, name: newName)
                }
            }
            .sheet(item: $feedVM.viewingEntry) { entry in
                RecordingDetailSheet(entry: entry, store: store)
            }
            .sheet(isPresented: $composeVM.showCamera) {
                CameraPickerView { image in
                    Task { await composeVM.addImage(image) }
                }
            }
            .photosPicker(
                isPresented: $composeVM.showPhotoPicker,
                selection: $composeVM.photoPickerItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: composeVM.showPhotoPicker) { _, isPresented in
                // Clear picker items when dismissed (memory safety)
                if !isPresented {
                    composeVM.photoPickerItems = []
                }
            }
            .onChange(of: composeVM.photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await composeVM.addPhotoPickerItems(newItems)
                    composeVM.photoPickerItems = []
                }
            }
            .fileImporter(
                isPresented: $composeVM.showFileImporter,
                allowedContentTypes: [.pdf, .plainText, .image, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await composeVM.addFile(result) }
            }
        }
        .preferredColorScheme(.light)
        .tagActionOverlay() // Toast overlay for actions
        .tagActionSheets() // Sheets for mail/share
        .onAppear {
            setupCallbacks()
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.91, green: 0.87, blue: 0.80),
                Color(red: 0.87, green: 0.83, blue: 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerBackground: some View {
        ZStack {
            Color(red: 0.91, green: 0.87, blue: 0.80).opacity(0.5)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.91, green: 0.87, blue: 0.80), location: 0),
                    .init(color: Color(red: 0.91, green: 0.87, blue: 0.80), location: 0.6),
                    .init(color: Color(red: 0.91, green: 0.87, blue: 0.80).opacity(0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 16) {
            Button {
                feedVM.selectAll(from: store.recordings)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16))
            }
            Button(role: .destructive) {
                let entriesToDelete = store.recordings.filter { feedVM.selectedIDs.contains($0.id) }
                store.deleteMultiple(entriesToDelete)
                feedVM.clearSelection()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
            }
            .disabled(feedVM.selectedIDs.isEmpty)
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(showChips: Bool, isNormalRecording: Bool) -> some View {
        VStack(spacing: 8) {
            // Chips strip
            if showChips {
                DraftChipsView(
                    audioItems: composeVM.draft.audioItems,
                    attachments: composeVM.draft.attachments,
                    onRemoveAudio: { composeVM.draft.removeAudioItem(id: $0) },
                    onRemoveAttachment: { composeVM.draft.removeAttachment(id: $0) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Quick record hint
            if composeVM.quickRecordState == .holding || composeVM.quickRecordState == .locked {
                Text(composeVM.quickRecordState == .locked ? "Stop recording to send" : "Release to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            // Main compose bar
            ComposeBar(
                viewModel: composeVM,
                isTextFieldFocused: $isTextFieldFocused,
                isShowingRecordingUI: isShowingRecordingUI,
                onNormalRecordTap: { handleNormalRecordTap() },
                onShowPermissionAlert: { showingPermissionAlert = true },
                onStopQuickRecord: { handleQuickRecordStop() }
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .background(alignment: .bottom) {
            bottomBarBackground
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showChips)
        .animation(.easeInOut(duration: 0.18), value: isNormalRecording)
        .animation(.easeInOut(duration: 0.15), value: composeVM.draft.hasContent)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: composeVM.quickRecordState)
    }

    private var bottomBarBackground: some View {
        let showBackground = composeVM.draft.hasChips || composeVM.quickRecordState == .holding || composeVM.quickRecordState == .locked
        let bgColor = Color(red: 0.87, green: 0.83, blue: 0.76)
        
        // Background fills the container from bottom up
        // Gradient fades from solid (at bar level) to transparent
        // Solid fills down to bottom edge
        return GeometryReader { geo in
            VStack(spacing: 0) {
                // Gradient: 260pt height, 30% fade
                LinearGradient(
                    stops: [
                        .init(color: bgColor.opacity(0), location: 0),
                        .init(color: bgColor, location: 0.3),
                        .init(color: bgColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
                
                // Solid fills remaining space to bottom
                bgColor
                    .frame(height: geo.size.height + geo.safeAreaInsets.bottom)
            }
            .frame(height: geo.size.height + geo.safeAreaInsets.bottom + 300)
            .offset(y: -geo.safeAreaInsets.bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .opacity(showBackground ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: showBackground)
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        composeVM.onSubmit = { [self] draft in
            submitDraft(draft)
        }
        composeVM.onRequestPermission = { [self] in
            showingPermissionAlert = true
        }
        composeVM.onTranscriptUpdate = { [self] entryID, transcript in
            store.updateTranscript(for: entryID, transcript: transcript)
        }
        composeVM.onShowRecordingWarning = { [self] duration in
            recordingDurationAtWarning = duration
            showingRecordingWarning = true
            stopRecordingCheckTimer()
        }
        composeVM.onShowError = { [self] message in
            errorMessage = message
            showingErrorAlert = true
        }
    }
    
    private func startRecordingCheckTimer() {
        stopRecordingCheckTimer()
        recordingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak composeVM] _ in
            guard let composeVM = composeVM else { return }
            Task { @MainActor in
                composeVM.checkRecordingDuration()
            }
        }
    }
    
    private func stopRecordingCheckTimer() {
        recordingCheckTimer?.invalidate()
        recordingCheckTimer = nil
    }

    // MARK: - Actions

    private func handleEntryTap(_ entry: RecordingEntry) {
        if isTextFieldFocused {
            isTextFieldFocused = false
        } else if feedVM.selectionMode {
            feedVM.toggleSelection(for: entry.id)
        } else {
            feedVM.viewingEntry = entry
        }
    }

    private func handleNormalRecordTap() {
        // Stop if already recording
        if composeVM.isRecording || isShowingRecordingUI {
            stopNormalRecording()
            return
        }

        Task {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .undetermined:
                let granted = await composeVM.recordingService.requestPermission()
                if granted {
                    await startNormalRecording()
                } else {
                    showingPermissionAlert = true
                }
            case .denied:
                showingPermissionAlert = true
            case .granted:
                await startNormalRecording()
            @unknown default:
                showingPermissionAlert = true
            }
        }
    }

    private func startNormalRecording() async {
        isShowingRecordingUI = true
        await Task.yield()
        do {
            try composeVM.recordingService.startRecording()
            composeVM.transcriptionService.startStreaming()
            startRecordingCheckTimer()
            isShowingRecordingUI = false
        } catch {
            isShowingRecordingUI = false
            showingPermissionAlert = true
        }
    }

    private func stopNormalRecording() {
        isShowingRecordingUI = false
        stopRecordingCheckTimer()
        guard let item = composeVM.stopNormalRecording() else { return }
        
        // Process the recording with retry
        Task {
            let (transcript, success) = await composeVM.transcribeWithRetry(fileURL: item.url)
            
            if success && ComposeViewModel.isValidTranscriptStatic(transcript) {
                // Update the draft item with transcript
                if let idx = composeVM.draft.audioItems.firstIndex(where: { $0.id == item.id }) {
                    composeVM.draft.audioItems[idx].transcript = transcript
                    composeVM.draft.audioItems[idx].isTranscribing = false
                }
            } else {
                // Remove invalid/failed recording
                composeVM.draft.removeAudioItem(id: item.id)
            }
        }
    }

    private func handleQuickRecordStop() {
        stopRecordingCheckTimer()
        composeVM.stopQuickRecord { entry in
            guard let entry = entry else {
                // Check if there was an error message to display
                if let error = composeVM.lastError {
                    errorMessage = error
                    showingErrorAlert = true
                    composeVM.lastError = nil
                }
                return
            }
            store.add(entry)

            // Generate title and tags
            Task {
                let finalTitle = await TitleService.shared.generateTitle(for: entry.transcript ?? "")
                store.updateName(for: entry.id, name: finalTitle)
                store.updateAudioTitle(for: entry.id, title: finalTitle)

                async let tags = TagService.shared.generateTags(for: entry.transcript ?? "")
                let finalTags = await tags
                store.updateTags(for: entry.id, tags: finalTags)
            }
        }
    }

    // MARK: - Draft Submission

    private func submitDraft(_ draft: ComposeDraft) {
        let textContent = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaAttachments = draft.attachments.map {
            MediaAttachment(id: $0.id, url: $0.url, type: $0.type)
        }

        let primaryAudio = draft.audioItems.first
        let additionalAudioItems = Array(draft.audioItems.dropFirst())
        let audioAttachments = additionalAudioItems.map {
            MediaAttachment(id: $0.id, url: $0.url, type: .audio, transcript: $0.transcript)
        }

        let allTranscripts = draft.audioItems.compactMap { $0.transcript }.filter { !$0.isEmpty }
        let hasTextSources = !allTranscripts.isEmpty || !textContent.isEmpty
        let hasAttachments = !mediaAttachments.isEmpty
        let hasTitleSources = hasTextSources || hasAttachments
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

        // Handle pending transcriptions
        if !inFlightIDs.isEmpty {
            recordingForEntryID = entry.id
            recordingItemID = inFlightIDs.first

            // Wait for transcription to complete
            Task {
                // This would need the transcription completion callback
                // For now, simplified version
            }
        }

        // Generate title and tags
        if inFlightIDs.isEmpty && hasTitleSources {
            let entryID = entry.id
            
            Task {
                let finalTitle: String
                let tagSource: String
                
                if hasTextSources {
                    // Generate from text/transcript
                    let titleSources = allTranscripts.isEmpty ? [textContent] : allTranscripts
                    tagSource = ([textContent] + allTranscripts).filter { !$0.isEmpty }.joined(separator: " ")
                    finalTitle = await TitleService.shared.generateEntryTitle(for: titleSources)
                } else if hasAttachments {
                    // Generate from attachments only
                    finalTitle = await TitleService.shared.generateTitleFromAttachments(mediaAttachments)
                    tagSource = "Attachment: \(finalTitle)"
                } else {
                    finalTitle = "Note"
                    tagSource = ""
                }
                
                async let tags = TagService.shared.generateTags(for: tagSource)
                let (resolvedTitle, finalTags) = await (finalTitle, tags)
                store.updateName(for: entryID, name: resolvedTitle)
                store.updateTags(for: entryID, tags: finalTags)
            }

            if let t = primaryAudio?.transcript, !t.isEmpty {
                Task {
                    let clipTitle = await TitleService.shared.generateTitle(for: t)
                    store.updateAudioTitle(for: entryID, title: clipTitle)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let t = Int(duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
