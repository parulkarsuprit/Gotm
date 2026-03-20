import Foundation
import FoundationModels

@MainActor
final class TitleService {
    static let shared = TitleService()
    private init() {}

    func generateTitle(for transcript: String) async -> String {
        guard #available(iOS 26.0, *) else {
            return fallbackTitle(from: transcript)
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return fallbackTitle(from: transcript)
        }

        do {
            let session = LanguageModelSession(
                instructions: """
                You generate short, smart titles for voice note transcriptions.
                Rules:
                - Maximum 6 words
                - Capture the core intent or action, not just a summary of details
                - Use title case
                - No punctuation at the end
                - No quotes, no explanation — only the title itself
                - Prefer action-oriented phrases (e.g. "Vet Trip Prep for Pixel")
                """
            )
            let response = try await session.respond(
                to: "Title this voice note: \(transcript)"
            )
            let title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? fallbackTitle(from: transcript) : title
        } catch {
            print("⚠️ [TitleService] Model error, using fallback: \(error)")
            return fallbackTitle(from: transcript)
        }
    }

    private func fallbackTitle(from transcript: String) -> String {
        let words = transcript.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? transcript : (words + (transcript.split(separator: " ").count > 5 ? "…" : ""))
    }
}
