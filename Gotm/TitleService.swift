import Foundation
import FoundationModels

@Generable
struct TitleOutput {
    @Guide(description: "A short title in title case, maximum 6 words, no punctuation at the end")
    var title: String
}

@MainActor
final class TitleService {
    static let shared = TitleService()
    private init() {}

    /// Generates a title for a single transcript (used for individual clip titles).
    func generateTitle(for transcript: String) async -> String {
        let words = transcript.split(separator: " ")
        if words.count <= 8 {
            return words.prefix(6).joined(separator: " ")
        }
        return await runModel(
            instructions: """
            You generate short, smart titles for voice note transcriptions.
            Rules:
            - Maximum 6 words
            - Capture the core idea or action
            - Use title case
            - No punctuation at the end
            """,
            prompt: "Title this voice note: \(transcript)",
            fallback: fallbackTitle(from: transcript)
        )
    }

    /// Generates an entry-level title from one or more clip transcripts.
    /// If clips cover unrelated topics, combines them as "Topic A + Topic B".
    /// If clips are thematically related, finds a single common title.
    func generateEntryTitle(for transcripts: [String]) async -> String {
        guard !transcripts.isEmpty else { return "Note" }
        if transcripts.count == 1 {
            return await generateTitle(for: transcripts[0])
        }

        let combinedWordCount = transcripts.joined(separator: " ").split(separator: " ").count
        if combinedWordCount <= 8 {
            return fallbackTitle(from: transcripts.joined(separator: " "))
        }

        let numbered = transcripts.enumerated()
            .map { "Recording \($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")

        return await runModel(
            instructions: """
            You generate short, smart titles for combined voice note entries.
            Rules:
            - Maximum 6 words total
            - Use title case
            - No punctuation at the end
            - If the recordings cover clearly different, unrelated topics, combine them as "Topic A + Topic B" (each part max 3 words)
            - If the recordings share a common theme or are related, write one unified title that captures the theme
            """,
            prompt: "Title this combined voice note entry:\n\(numbered)",
            fallback: fallbackTitle(from: transcripts[0])
        )
    }

    // MARK: - Private

    private func runModel(instructions: String, prompt: String, fallback: String) async -> String {
        guard #available(iOS 26.0, *) else {
            print("⚠️ [TitleService] iOS 26 not available — using fallback")
            return fallback
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("⚠️ [TitleService] Model unavailable: \(model.availability) — using fallback")
            return fallback
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: TitleOutput.self)
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return fallback }
            return title
        } catch {
            print("⚠️ [TitleService] Model error, using fallback: \(error)")
            return fallback
        }
    }

    private func fallbackTitle(from transcript: String) -> String {
        let words = transcript.split(separator: " ")
        return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "…" : "")
    }
}
