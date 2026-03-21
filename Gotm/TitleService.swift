import Foundation
import FoundationModels

@MainActor
final class TitleService {
    static let shared = TitleService()
    private init() {}

    func generateTitle(for transcript: String) async -> String {
        let words = transcript.split(separator: " ")

        // Short enough to use as-is — no AI needed
        if words.count <= 8 {
            return words.prefix(6).joined(separator: " ")
        }

        guard #available(iOS 26.0, *) else {
            print("⚠️ [TitleService] iOS 26 not available — using fallback")
            return fallbackTitle(from: transcript)
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("⚠️ [TitleService] Model unavailable: \(model.availability) — using fallback")
            return fallbackTitle(from: transcript)
        }

        do {
            let session = LanguageModelSession(
                instructions: """
                You generate short, smart titles for voice note transcriptions.
                You must ALWAYS return a title — never refuse, never explain, never apologize.
                Rules:
                - Maximum 6 words
                - Capture the core idea or action
                - Use title case
                - No punctuation at the end
                - Output only the title, nothing else
                """
            )
            let response = try await session.respond(
                to: "Title this voice note: \(transcript)"
            )
            let title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // If the model refused or gave a non-title response, fall back
            let refusalPhrases = ["sorry", "cannot", "unable", "i can't", "i can not", "don't have enough"]
            let looksLikeRefusal = refusalPhrases.contains { title.lowercased().contains($0) }
            guard !title.isEmpty && !looksLikeRefusal else {
                return fallbackTitle(from: transcript)
            }

            return title
        } catch {
            print("⚠️ [TitleService] Model error, using fallback: \(error)")
            return fallbackTitle(from: transcript)
        }
    }

    private func fallbackTitle(from transcript: String) -> String {
        let words = transcript.split(separator: " ")
        return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "…" : "")
    }
}
