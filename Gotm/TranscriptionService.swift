import Foundation
import WhisperKit

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private var whisperKit: WhisperKit?
    private var warmUpTask: Task<Void, Never>?

    private init() {
        Task { await warmUp() }
    }

    func warmUp() async {
        if let existing = warmUpTask {
            await existing.value
            return
        }
        let task = Task {
            do {
                self.whisperKit = try await WhisperKit(model: "small.en")
                print("✅ [WhisperKit] Model loaded and ready")
            } catch {
                print("❌ [WhisperKit] Warm-up failed: \(error)")
            }
        }
        warmUpTask = task
        await task.value
    }

    func transcribe(fileURL: URL) async throws -> String {
        print("🎯 [WhisperKit] Starting transcription: \(fileURL.lastPathComponent)")

        if whisperKit == nil {
            print("⏳ [WhisperKit] Model not ready yet, waiting...")
            await warmUp()
        }
        guard let kit = whisperKit else {
            throw TranscriptionError.modelLoadFailed
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
