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

        Voice notes are stream-of-consciousness speech — full of filler words, incomplete thoughts, and wandering sentences. Your job is to cut through the noise and find the single most important idea FROM THE ACTUAL TRANSCRIPT, then express it as a title.

        CRITICAL RULES:
        - You MUST ONLY use words, concepts, and topics that appear IN THE TRANSCRIPT
        - NEVER hallucinate content that isn't in the transcript
        - NEVER use examples from this prompt as actual titles
        - If the transcript says "I'm halfway through this joint", the title must reference THAT content — not "Dentist" or "Tuesday" or anything unrelated

        HOW TO EXTRACT THE TITLE:
        1. Read the transcript carefully
        2. Identify what the user ACTUALLY said — find the core subject and intent
        3. Use the user's OWN WORDS or close paraphrases — never invent new topics
        4. Construct the title as: [Action or Topic] + [Subject] + [Essential Context only if it fits]

        TITLE RULES:
        - Title Case: Capitalize All Major Words
        - 5–10 words ideal, 12 words absolute maximum
        - No trailing punctuation of any kind
        - Use ONLY content from the transcript — if "dentist" isn't mentioned, it cannot be in the title
        - When there is a task or action, lead with the verb
        - When it is information, lead with the topic
        - Strip filler words: um, uh, like, so, basically, you know, right, okay, I mean, actually, literally

        EXAMPLES OF CORRECT BEHAVIOR:
        Transcript: "Hi how are you doing I'm still halfway through this joint"
        Title: "Halfway Through This Joint"
        
        Transcript: "Need to call the dentist about Tuesday"
        Title: "Call Dentist About Tuesday Appointment"

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
        let fallbackInstructions = """
            Create a title (5–12 words, Title Case, no punctuation) using ONLY words and concepts from this transcript. \
            Do not add information not in the text. Output only the title.
            """
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
            
            // Validate title is related to transcript content
            guard isTitleRelatedToTranscript(raw, transcript: prompt) else {
                print("⚠️ [TitleService] Generated title '\(raw)' unrelated to transcript - rejecting")
                return nil
            }
            
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
    
    /// Validates that the generated title contains content actually present in the transcript
    private func isTitleRelatedToTranscript(_ title: String, transcript: String) -> Bool {
        let titleLower = title.lowercased()
        let transcriptLower = transcript.lowercased()
        
        // Split title into meaningful words (ignore common words)
        let commonWords: Set<String> = [
            "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
            "by", "from", "up", "out", "as", "is", "are", "was", "were", "be", "been",
            "being", "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "about", "this", "that"
        ]
        
        let titleWords = titleLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 && !commonWords.contains($0) }
        
        guard !titleWords.isEmpty else { return true } // Too short to validate meaningfully
        
        // At least 50% of significant title words should appear in transcript
        let matchingWords = titleWords.filter { transcriptLower.contains($0) }
        let matchRatio = Double(matchingWords.count) / Double(titleWords.count)
        
        if matchRatio < 0.5 {
            print("⚠️ [TitleService] Title content mismatch: \(matchingWords.count)/\(titleWords.count) words match")
            return false
        }
        
        return true
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
