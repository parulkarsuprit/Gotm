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

    // MARK: - Local State
    @State private var isShowingRecordingUI = false
    @State private var showingPermissionAlert = false
    @State private var recordingForEntryID: UUID?
    @State private var recordingItemID: UUID?
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        let isNormalRecording = (isShowingRecordingUI || composeVM.isRecording) && composeVM.quickRecordState == .idle
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
            .sheet(item: $feedVM.editingEntry) { entry in
                RenameSheet(entry: entry) { newName in
                    store.updateName(for: entry.id, name: newName)
                }
            }
            .sheet(item: $feedVM.viewingEntry) { entry in
                RecordingDetailSheet(entry: entry)
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
        .onAppear {
            setupCallbacks()
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
                feedVM.onDelete = { ids in
                    for entry in store.recordings.filter({ ids.contains($0.id) }) {
                        store.delete(entry)
                    }
                }
                feedVM.deleteSelected()
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
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.87, green: 0.83, blue: 0.76), location: 0),
                .init(color: Color(red: 0.87, green: 0.83, blue: 0.76), location: 0.7),
                .init(color: Color(red: 0.87, green: 0.83, blue: 0.76).opacity(0), location: 1.0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: 160)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .opacity(composeVM.quickRecordState == .holding || composeVM.quickRecordState == .locked || composeVM.draft.hasChips ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: composeVM.quickRecordState)
        .animation(.easeInOut(duration: 0.25), value: composeVM.draft.hasChips)
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        composeVM.onSubmit = { [self] draft in
            submitDraft(draft)
        }
        composeVM.onRequestPermission = { [self] in
            showingPermissionAlert = true
        }
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

    private func handleQuickRecordStop() {
        composeVM.stopQuickRecord { entry in
            guard let entry = entry else { return }
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
            let titleSources = allTranscripts.isEmpty ? [textContent] : allTranscripts

            Task {
                let tagSource = ([textContent] + allTranscripts).filter { !$0.isEmpty }.joined(separator: " ")
                async let title = TitleService.shared.generateEntryTitle(for: titleSources)
                async let tags = TagService.shared.generateTags(for: tagSource)
                let (finalTitle, finalTags) = await (title, tags)
                store.updateName(for: entryID, name: finalTitle)
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
}

// MARK: - Preview

#Preview {
    ContentView()
}
