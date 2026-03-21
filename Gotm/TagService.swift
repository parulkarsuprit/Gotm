import Foundation
import FoundationModels

// MARK: - Foundation Models structured output

@Generable
struct TagIntentOutput {
    @Guide(description: "True if the note describes a concrete task, next step, or action the person intends to do (e.g. 'I need to call Sarah', 'finish the report')")
    var isAction: Bool

    @Guide(description: "True if the note contains a creative idea, 'what if' exploration, insight, or non-actionable concept")
    var isIdea: Bool

    @Guide(description: "True if the note captures a firm decision or commitment that has been made ('we'll go with X', 'I decided', 'let's do this')")
    var isDecision: Bool
}

// MARK: - TagService

@MainActor
final class TagService {
    static let shared = TagService()
    private init() {}

    func generateTags(for text: String) async -> [EntryTag] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var tags: [EntryTag] = []

        // Layer 1: fast rule-based extractors (run synchronously, no AI cost)
        tags += ruleTags(for: text)

        // Layer 2: Foundation Models for nuanced intent tags (Action / Idea / Decision)
        // Only run if those tags aren't already covered by rules
        let existingTypes = Set(tags.map { $0.type })
        let needsModel = !existingTypes.contains(.action)
                      || !existingTypes.contains(.idea)
                      || !existingTypes.contains(.decision)
        if needsModel {
            tags += await modelIntentTags(for: text, skipping: existingTypes)
        }

        // Deduplicate (keep highest confidence per type) and sort by feed priority
        var best: [TagType: EntryTag] = [:]
        for tag in tags {
            if let existing = best[tag.type] {
                if tag.confidence > existing.confidence { best[tag.type] = tag }
            } else {
                best[tag.type] = tag
            }
        }

        return best.values.sorted { $0.type.feedPriority < $1.type.feedPriority }
    }

    // MARK: - Rule-based layer

    private func ruleTags(for text: String) -> [EntryTag] {
        let lower = text.lowercased()
        var tags: [EntryTag] = []

        // Question — high detectability, auto-apply
        if let trigger = matchQuestion(lower) {
            tags.append(EntryTag(type: .question, status: .auto, confidence: 0.90, triggerText: trigger))
        }

        // Reminder — suggested (can be wrong on casual "by" usage)
        if let trigger = matchReminder(lower) {
            tags.append(EntryTag(type: .reminder, status: .suggested, confidence: 0.82, triggerText: trigger))
        }

        // Event — suggested (needs time + meeting verb combo)
        if let trigger = matchEvent(lower) {
            tags.append(EntryTag(type: .event, status: .suggested, confidence: 0.78, triggerText: trigger))
        }

        // Reference — auto-apply, low harm if wrong
        if let trigger = matchReference(lower) {
            tags.append(EntryTag(type: .reference, status: .auto, confidence: 0.88, triggerText: trigger))
        }

        // Purchase — auto-apply with figurative guard
        if let trigger = matchPurchase(lower) {
            tags.append(EntryTag(type: .purchase, status: .auto, confidence: 0.85, triggerText: trigger))
        }

        // Money — suggested (privacy sensitive)
        if let trigger = matchMoney(text) {  // use original case for currency symbols
            tags.append(EntryTag(type: .money, status: .suggested, confidence: 0.90, triggerText: trigger))
        }

        // Person — auto-apply with quick-remove affordance (PII)
        if let trigger = matchPerson(text) {
            tags.append(EntryTag(type: .person, status: .auto, confidence: 0.80, triggerText: trigger))
        }

        // Rule-based action signals (strong imperative patterns only)
        if let trigger = matchActionRules(lower) {
            tags.append(EntryTag(type: .action, status: .suggested, confidence: 0.75, triggerText: trigger))
        }

        return tags
    }

    // MARK: - Rule matchers

    private func matchQuestion(_ lower: String) -> String? {
        // Ends with question mark
        if lower.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).hasSuffix("?") {
            return nil  // Will be caught below
        }
        let questionEnding = lower.contains("?")
        if questionEnding { return "?" }

        // Leading wh-words or question phrases
        let patterns = [
            "how do i", "how do we", "how can i", "how can we", "how should",
            "what's the best", "what is the best", "what would",
            "should i", "should we", "should it",
            "which one", "which is", "which should",
            "why is", "why does", "why would",
            "wondering if", "not sure if", "not sure how", "not sure what",
            "i don't know", "i dont know", "figure out", "figuring out",
            "need to decide", "trying to decide"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchReminder(_ lower: String) -> String? {
        let strongPatterns = [
            "remind me", "don't forget", "dont forget",
            "remember to", "make sure to", "make sure i", "don't let me forget",
            "follow up", "follow-up", "circle back", "check in on",
            "get back to", "need to get back"
        ]
        if let m = firstMatch(in: lower, patterns: strongPatterns) { return m }

        // Deadline patterns ("by friday", "by end of", "before monday")
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                    "tomorrow", "end of day", "eod", "end of week", "end of month"]
        for day in days {
            if lower.contains("by \(day)") { return "by \(day)" }
            if lower.contains("before \(day)") { return "before \(day)" }
        }
        return nil
    }

    private func matchEvent(_ lower: String) -> String? {
        let meetingVerbs = ["meeting", "appointment", "call with", "sync with",
                            "catch up with", "catchup with", "session with",
                            "scheduled", "schedule a", "book a", "booked"]
        guard let verb = firstMatch(in: lower, patterns: meetingVerbs) else { return nil }

        // Must also contain a time reference
        let timeWords = ["tomorrow", "today", "monday", "tuesday", "wednesday", "thursday",
                         "friday", "saturday", "sunday", "next week", "this week",
                         "at ", "am", "pm", "noon", "morning", "afternoon", "evening"]
        guard timeWords.contains(where: { lower.contains($0) }) else { return nil }
        return verb
    }

    private func matchReference(_ lower: String) -> String? {
        // URLs
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return "link"
        }
        // File extensions
        let extensions = [".pdf", ".doc", ".docx", ".pptx", ".xlsx", ".csv", ".txt", ".md"]
        if let ext = extensions.first(where: { lower.contains($0) }) { return ext }

        // Reference language
        let patterns = [
            "that article", "that post", "that paper", "that video", "that podcast",
            "the article", "the paper", "the report", "the deck", "the doc",
            "read that", "check out", "look at that", "link to", "that link",
            "that thread", "that repo"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchPurchase(_ lower: String) -> String? {
        // Guard figurative uses first
        let figurative = ["buy into", "buy that idea", "buy the idea", "buying into"]
        if figurative.contains(where: { lower.contains($0) }) { return nil }

        let patterns = [
            "buy ", "order ", "purchase ", "get more ", "pick up ",
            "subscribe to", "sign up for", "add to cart",
            "need to order", "need to buy", "need to get more"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchMoney(_ text: String) -> String? {
        // Currency symbols (use original case text)
        let symbols = ["$", "£", "€", "₹", "¥"]
        if let sym = symbols.first(where: { text.contains($0) }) { return sym }

        let lower = text.lowercased()
        // Guard: avoid dimension/measurement false positives
        let dimensionGuard = ["cm", "mm", "kg", "km", "gb", "mb", "px", "pt", "deg"]
        let words = lower.split(separator: " ")
        for word in words {
            let w = String(word)
            if dimensionGuard.contains(where: { w.hasSuffix($0) }) { continue }
            // Number pattern like "5k", "100k", followed by budget words
        }

        let patterns = [
            "budget", "cost ", "costs ", "price ", "pricing",
            "payment", "invoice", "fee ", "fees", "spend ",
            "spending", "expense", "expenses", "reimburs",
            "dollars", "rupees", "euros", "pounds"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchPerson(_ text: String) -> String? {
        // Look for capitalized name after social/action verbs
        let verbPatterns = ["with ", "tell ", "email ", "ask ", "call ", "meet ", "message ",
                            "contact ", "cc ", "talk to ", "update ", "inform "]
        let words = text.components(separatedBy: .whitespaces)

        for (i, word) in words.enumerated() {
            let lw = word.lowercased()
            guard verbPatterns.contains(where: { lw.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }) else { continue }
            // Check next word is a capitalized proper noun (not "I", not a common word)
            let nextIndex = i + 1
            guard nextIndex < words.count else { continue }
            let next = words[nextIndex].trimmingCharacters(in: .punctuationCharacters)
            guard next.count > 1,
                  next.first?.isUppercase == true,
                  next.first?.isLetter == true,
                  !commonWords.contains(next.lowercased())
            else { continue }
            return next
        }
        return nil
    }

    private func matchActionRules(_ lower: String) -> String? {
        // Strong imperative rule patterns only — model handles the nuanced cases
        let patterns = [
            "remind me to", "need to ", "need to get",
            "i should ", "we should ", "have to ",
            "next step", "next steps", "action item", "todo:", "to do:",
            "follow up on", "finish ", "complete ", "send ", "submit "
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    // MARK: - Foundation Models intent layer

    private func modelIntentTags(for text: String, skipping: Set<TagType>) async -> [EntryTag] {
        guard #available(iOS 26.0, *) else { return [] }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return [] }

        do {
            let session = LanguageModelSession(
                instructions: """
                You classify short voice or text notes into intent categories.
                Be conservative — only return true when clearly evident in the text.
                """
            )
            let response = try await session.respond(
                to: "Classify this note: \"\(text)\"",
                generating: TagIntentOutput.self
            )
            let output = response.content
            var tags: [EntryTag] = []

            if output.isAction && !skipping.contains(.action) {
                tags.append(EntryTag(type: .action, status: .suggested, confidence: 0.80))
            }
            if output.isIdea && !skipping.contains(.idea) {
                tags.append(EntryTag(type: .idea, status: .auto, confidence: 0.82))
            }
            if output.isDecision && !skipping.contains(.decision) {
                tags.append(EntryTag(type: .decision, status: .suggested, confidence: 0.78))
            }
            return tags
        } catch {
            print("⚠️ [TagService] Model error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers

    private func firstMatch(in text: String, patterns: [String]) -> String? {
        patterns.first(where: { text.contains($0) })
    }

    private let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
        "my", "our", "your", "their", "this", "that", "these", "those",
        "it", "its", "he", "she", "we", "they", "you", "me", "him", "her", "us", "them",
        "i", "not", "no", "yes", "ok", "okay", "just", "also", "so", "then",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]
}
