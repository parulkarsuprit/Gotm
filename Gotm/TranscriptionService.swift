import Foundation
import WhisperKit

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private var whisperKit: WhisperKit?

    private init() {
        Task { await warmUp() }
    }

    // Pre-load the model as soon as the app launches so the first transcription is instant
    func warmUp() async {
        guard whisperKit == nil else { return }
        do {
            whisperKit = try await WhisperKit(model: "small.en")
            print("✅ [WhisperKit] Model loaded and ready")
        } catch {
            print("❌ [WhisperKit] Warm-up failed: \(error)")
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        print("🎯 [WhisperKit] Starting transcription: \(fileURL.lastPathComponent)")

        var kit: WhisperKit
        if let existing = whisperKit {
            kit = existing
        } else {
            print("⏳ [WhisperKit] Model not ready yet, loading now...")
            let loaded = try await WhisperKit(model: "small.en")
            whisperKit = loaded
            kit = loaded
        }

        let options = DecodingOptions(task: .transcribe, language: "en", withoutTimestamps: true)
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("✅ [WhisperKit] Done: \(text.prefix(80))...")
        return text
    }
}

enum TranscriptionError: Error {
    case modelLoadFailed
    case inferenceFailed
}
