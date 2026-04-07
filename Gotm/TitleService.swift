import Foundation
import FoundationModels

@MainActor
final class TitleService {
    static let shared = TitleService()
    private init() {}
    
    /// Track if title generation failed
    private(set) var lastError: TitleError?
    
    enum TitleError: Error {
        case modelUnavailable
        case generationFailed
        case emptyResult
        
        var message: String {
            switch self {
            case .modelUnavailable: return "AI features unavailable"
            case .generationFailed: return "Could not generate title"
            case .emptyResult: return "Empty transcript"
            }
        }
    }

    func generateTitle(for transcript: String) async -> String {
        lastError = nil
        let result = await runModel(prompt: transcript)
        if result == "Note" && !transcript.isEmpty {
            lastError = .generationFailed
        }
        return result
    }

    func generateEntryTitle(for transcripts: [String]) async -> String {
        guard !transcripts.isEmpty else { return "Note" }
        if transcripts.count == 1 { return await generateTitle(for: transcripts[0]) }
        let combined = transcripts.enumerated()
            .map { "Recording \($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
        return await runModel(prompt: combined)
    }

    // MARK: - Private

    private let instructions = """
        You are an expert at distilling rambling, unstructured voice notes into sharp, memorable titles.

        Voice notes are stream-of-consciousness speech — full of filler words, incomplete thoughts, and wandering sentences. Your job is to cut through the noise and find the single most important idea, then express it as a title that instantly recalls the note's purpose days later.

        HOW TO EXTRACT THE TITLE:
        1. Identify the core intent — is this a task, reminder, idea, decision, plan, observation, or piece of information?
        2. Find the key subject — what person, project, place, object, or concept is at the centre?
        3. Determine the action or angle — what needs to happen, what was decided, or what is the main point?
        4. Construct the title as: [Action or Topic] + [Subject] + [Essential Context only if it fits]

        TITLE RULES:
        - Title Case: Capitalize All Major Words. Do not capitalize articles (a, an, the), short prepositions (in, on, at, for, of, to, with), or coordinating conjunctions (and, but, or) unless they are the first word
        - 5–10 words ideal, 12 words absolute maximum
        - No trailing punctuation of any kind
        - Be specific — "Fix Checkout Crash on Payment Screen" beats "App Bug"
        - Be concrete — "Call Dentist to Reschedule Tuesday Appointment" beats "Health Stuff"
        - When there is a task or action, lead with the verb: "Book Flights", "Follow Up With", "Review Before"
        - When it is information or an observation, lead with the topic: "Flight Details for Tokyo", "Meeting Notes from Product Review"
        - When it is an idea, lead with the idea itself — not the word "Idea": "Offline Mode for the App", "Dark Theme for Settings Screen"
        - If the note covers multiple topics, pick the dominant one — do not list them all
        - Strip all filler: um, uh, like, so, basically, you know, right, okay, I mean, actually, literally

        OUTPUT: Only the title. No explanation, no quotation marks, no extra text whatsoever.
        """

    private func runModel(prompt: String) async -> String {
        guard #available(iOS 26.0, *) else { return extractTitleFallback(from: prompt) }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return extractTitleFallback(from: prompt) }

        // First attempt — full instructions
        if let title = await attempt(instructions: instructions, prompt: prompt) {
            return title
        }

        // Retry with a stripped-down prompt — guardrail may have fired on content in the instructions
        let fallbackInstructions = "Generate a Title Case title (5–12 words, no trailing punctuation) that summarises this voice note. Output only the title."
        if let title = await attempt(instructions: fallbackInstructions, prompt: prompt) {
            return title
        }

        // Final fallback: extract from transcript
        return extractTitleFallback(from: prompt)
    }
    
    private func extractTitleFallback(from text: String) -> String {
        // Clean up the text
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get first 6-8 words
        let words = cleaned.split(separator: " ")
        let wordCount = min(words.count, 8)
        guard wordCount > 0 else { return "Note" }
        
        var titleWords = Array(words.prefix(wordCount))
        
        // Remove common filler words at the start
        let fillerWords: Set<String> = ["um", "uh", "like", "so", "okay", "well", "right"]
        while let first = titleWords.first?.lowercased(), fillerWords.contains(first) {
            titleWords.removeFirst()
        }
        
        guard !titleWords.isEmpty else { return "Note" }
        
        let title = titleWords.joined(separator: " ")
        return applyTitleCase(String(title))
    }

    private func attempt(instructions: String, prompt: String) async -> String? {
        guard #available(iOS 26.0, *) else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let raw = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: ")")))

            guard !raw.isEmpty, !isGarbageTitle(raw) else { return nil }
            return applyTitleCase(raw)
        } catch let error as LanguageModelSession.GenerationError {
            if case .guardrailViolation = error {
                print("⚠️ [TitleService] Guardrail hit — retrying with minimal prompt")
            } else {
                print("⚠️ [TitleService] Generation error: \(error)")
            }
            return nil
        } catch {
            print("⚠️ [TitleService] Failed: \(error)")
            return nil
        }
    }

    private func applyTitleCase(_ text: String) -> String {
        let neverCapitalize: Set<String> = [
            "a", "an", "the",
            "and", "but", "or", "nor", "so", "yet",
            "in", "on", "at", "for", "of", "to", "with", "by", "from", "up", "out", "as"
        ]
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            // Always capitalize first and last word
            if index == 0 || index == words.count - 1 {
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            return neverCapitalize.contains(lower) ? lower : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func isGarbageTitle(_ title: String) -> Bool {
        let lower = title.lowercased()

        // Refusal or meta openers
        let badPrefixes = [
            "i'm sorry", "i am sorry", "i cannot", "i can't", "as a chatbot",
            "as a language model", "as an ai", "certainly!", "sure!", "of course!",
            "i'd be happy", "i would be happy", "i apologize", "here is", "here's",
            "sorry, i cannot", "sorry, i can't", "sorry i cannot", "sorry i can't",
            "i'm unable to", "i am unable to", "unable to assist", "cannot assist",
            "i'm not able to", "i am not able to"
        ]
        if badPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        
        // Contains refusal phrases anywhere
        let refusalPhrases = [
            "cannot assist", "can't assist", "unable to assist",
            "sorry, i cannot", "sorry, i can't", "not able to assist"
        ]
        if refusalPhrases.contains(where: { lower.contains($0) }) { return true }

        // Titles must be a single line
        if title.contains("\n") { return true }

        // Titles must not exceed 12 words
        if title.split(separator: " ").count > 12 { return true }
        
        // Must not be too short
        if title.count < 3 { return true }

        return false
    }
}
