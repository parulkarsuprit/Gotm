import AVFoundation
import Observation
import SwiftUI
import PhotosUI

// MARK: - Draft Types

struct DraftAudioItem: Identifiable {
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

struct DraftAttachment: Identifiable {
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

@Observable
final class ComposeDraft {
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

    func removeAudioItem(id: UUID) {
        if let idx = audioItems.firstIndex(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: audioItems[idx].url)
            audioItems.remove(at: idx)
        }
    }

    func removeAttachment(id: UUID) {
        if let idx = attachments.firstIndex(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: attachments[idx].url)
            attachments.remove(at: idx)
        }
    }
    
    /// Clean up all files when draft is discarded
    func cleanupAllFiles() {
        for item in audioItems {
            try? FileManager.default.removeItem(at: item.url)
        }
        for attachment in attachments {
            try? FileManager.default.removeItem(at: attachment.url)
        }
        audioItems.removeAll()
        attachments.removeAll()
    }
}

enum QuickRecordState: Equatable {
    case idle
    case holding   // long press active, user still holding
    case locked    // swiped to lock, hands-free
    case processing // recording stopped, transcribing
}

@MainActor
@Observable
final class ComposeViewModel {
    // MARK: - Dependencies
    let recordingService = RecordingService.shared
    let transcriptionService = TranscriptionService.shared
    let rewriteSettings = RewriteSettings.shared
    var onSubmit: ((ComposeDraft) -> Void)?
    var onRequestPermission: (() -> Void)?
    var onTranscriptUpdate: ((UUID, String) -> Void)?
    var onShowError: ((String) -> Void)?

    // MARK: - State
    var draft = ComposeDraft()
    var quickRecordState: QuickRecordState = .idle
    var showAttachmentMenu = false
    var lastError: String?

    // MARK: - Quick Record State
    var quickDragOffset: CGFloat = 0
    var quickPressTask: Task<Void, Never>?
    var quickPressStart: Date?
    let lockThreshold: CGFloat = 240

    var lockProgress: CGFloat {
        min(1.0, abs(quickDragOffset) / lockThreshold)
    }

    var isRecording: Bool {
        recordingService.isRecording
    }

    var recordingLevel: Double {
        recordingService.recordingLevel
    }

    var elapsedTime: TimeInterval {
        recordingService.elapsedTime
    }

    // MARK: - Picker State
    var showPhotoPicker = false
    var showFileImporter = false
    var showCamera = false
    var photoPickerItems: [PhotosPickerItem] = []

    // MARK: - Recording Duration Warning
    private var longRecordingWarningShown = false
    var onShowRecordingWarning: ((TimeInterval) -> Void)?
    
    // MARK: - Recording Actions

    func startQuickRecord() {
        quickPressTask = nil
        quickPressStart = nil

        Task {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .undetermined:
                let granted = await recordingService.requestPermission()
                guard granted else {
                    onRequestPermission?()
                    return
                }
            case .denied:
                onRequestPermission?()
                return
            case .granted:
                break
            @unknown default:
                return
            }

            do {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    quickRecordState = .holding
                }
                try recordingService.startRecording()
                transcriptionService.startStreaming()
            } catch {
                quickRecordState = .idle
                onRequestPermission?()
            }
        }
    }

    func lockQuickRecord() {
        guard quickRecordState == .holding else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            quickRecordState = .locked
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        quickDragOffset = 0
    }
    
    /// Call this periodically during recording to check duration
    func checkRecordingDuration() {
        let duration = recordingService.elapsedTime
        let thirtyMinutes: TimeInterval = 30 * 60
        
        // Show warning at 30 minutes if not already shown
        if duration >= thirtyMinutes && !longRecordingWarningShown {
            longRecordingWarningShown = true
            onShowRecordingWarning?(duration)
        }
        
        // Auto-stop only in critical conditions
        let batteryLevel = UIDevice.current.batteryLevel
        let isLowBattery = batteryLevel > 0 && batteryLevel <= 0.10  // 10% or less
        
        if isLowBattery && duration > 60 {
            // Stop recording to save battery, but only after at least 1 min
            _ = recordingService.stopRecording()
            quickRecordState = .idle
        }
    }
    
    /// Call when user confirms to continue recording past warning
    func continueRecording() {
        // Just resets the flag so we don't show again immediately
        // (we'll show again at 60 min, 90 min, etc.)
        longRecordingWarningShown = false
    }

    func stopQuickRecord(onComplete: @escaping (RecordingEntry?) -> Void) {
        guard quickRecordState == .holding || quickRecordState == .locked else { return }
        guard let (fileURL, duration) = recordingService.stopRecording() else {
            withAnimation { quickRecordState = .idle }
            onComplete(nil)
            return
        }

        // Discard accidental presses — nothing under 1 second is intentional
        guard duration >= 1.0 else {
            try? FileManager.default.removeItem(at: fileURL)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                quickRecordState = .idle
            }
            onComplete(nil)
            return
        }
        
        // Check audio quality immediately - reject silent recordings
        let qualityCheck = recordingService.hasAcceptableAudioQuality()
        guard qualityCheck.isValid else {
            try? FileManager.default.removeItem(at: fileURL)
            recordingService.resetAudioQualityMetrics()
            // Instant state change - no animation delay
            quickRecordState = .idle
            // Haptic feedback for error
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // Store error for UI display
            lastError = qualityCheck.reason
            onComplete(nil)
            return
        }
        recordingService.resetAudioQualityMetrics()

        // Only show processing if we actually have audio to transcribe
        withAnimation(.easeInOut(duration: 0.2)) {
            quickRecordState = .processing
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            // Try transcription with retry logic
            let (transcript, success) = await transcribeWithRetry(fileURL: fileURL)
            
            guard success, isValidTranscript(transcript) else {
                try? FileManager.default.removeItem(at: fileURL)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    quickRecordState = .idle
                }
                onComplete(nil)
                return
            }

            let entry = RecordingEntry(
                name: "Loading…",
                isTitleLoading: true,
                duration: duration,
                audioURL: fileURL,
                transcript: transcript
            )

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                quickRecordState = .idle
            }

            // Fire refinement immediately with context-aware formatting
            Task { @MainActor in
                let base: String
                if let deepgram = await transcriptionService.refineWithDeepgram(fileURL: fileURL) {
                    base = deepgram
                } else {
                    base = transcript
                }
                
                // Apply AI formatting with context
                let context = self.rewriteSettings.rewriteContext()
                let formatted = await transcriptionService.formatWithAI(base, context: context)
                
                if formatted != base {
                    // Update the entry with the formatted transcript via callback
                    self.onTranscriptUpdate?(entry.id, formatted)
                }
            }

            onComplete(entry)
        }
    }
    
    /// Transcribe with up to 3 retry attempts (public for normal recording flow)
    func transcribeWithRetry(fileURL: URL, maxRetries: Int = 3) async -> (transcript: String, success: Bool) {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let transcript = try await transcriptionService.transcribe(fileURL: fileURL)
                return (transcript, true)
            } catch {
                lastError = error
                print("⚠️ [Transcription] Attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    // Wait before retry (exponential backoff: 1s, 2s, 4s)
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        print("❌ [Transcription] All \(maxRetries) attempts failed. Last error: \(lastError?.localizedDescription ?? "Unknown")")
        return ("", false)
    }

    // MARK: - Normal Recording (for attachment flow)

    func startNormalRecording() async -> Bool {
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .undetermined:
            let granted = await recordingService.requestPermission()
            return granted
        case .denied:
            return false
        case .granted:
            do {
                try recordingService.startRecording()
                transcriptionService.startStreaming()
                return true
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func stopNormalRecording() -> DraftAudioItem? {
        guard let (fileURL, duration) = recordingService.stopRecording() else { return nil }
        let item = DraftAudioItem(url: fileURL, duration: duration)
        draft.audioItems.append(item)
        return item
    }

    // MARK: - Submission

    func submit() {
        guard draft.hasContent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSubmit?(draft)
        draft = ComposeDraft()
    }

    // MARK: - Media Attachments

    func addImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            let url = try RecordingStore.saveMedia(data, fileExtension: "jpg")
            let attachment = DraftAttachment(url: url, type: .image, thumbnail: image)
            draft.attachments.append(attachment)
        } catch {
            print("❌ [Media] Failed to save image: \(error)")
        }
    }

    func addFile(_ result: Result<[URL], Error>) async {
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

    func addPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await addImage(image)
            }
        }
    }

    // MARK: - Validation

    static func isValidTranscriptStatic(_ text: String) -> Bool {
        return isValidTranscriptInternal(text)
    }

    private func isValidTranscript(_ text: String) -> Bool {
        return Self.isValidTranscriptInternal(text)
    }

    private static func isValidTranscriptInternal(_ text: String) -> Bool {
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
}
