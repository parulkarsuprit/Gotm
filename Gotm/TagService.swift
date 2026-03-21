import Foundation
import FoundationModels

// MARK: - Foundation Models structured output

@Generable
struct TagIntentOutput {
    @Guide(description: "True if the note describes a concrete task, next step, or action the person intends to do (e.g. 'I need to call Sarah', 'finish the report', 'send the email')")
    var isAction: Bool

    @Guide(description: "True if the note describes a scheduled commitment suited for a calendar: a meeting, call, appointment, or plan to meet/see someone at a specific time or day (e.g. 'meeting with John tomorrow', 'dentist next Tuesday', 'grabbing coffee with Sarah on Friday')")
    var isEvent: Bool

    @Guide(description: "True if the note contains a time-based nudge, deadline, or follow-up that is NOT a scheduled meeting — e.g. 'remind me to', 'don't forget', 'by Friday', 'follow up in two days', 'renew before end of month'")
    var isReminder: Bool

    @Guide(description: "True if the note contains something the user wants to figure out, research, or decide — includes rhetorical questions, 'I wonder', 'not sure if', 'should I', even without a question mark (common in voice notes)")
    var isQuestion: Bool

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

        // Layer 2: Foundation Models for nuanced intent tags
        // Run for any intent tag not already covered by rules
        let existingTypes = Set(tags.map { $0.type })
        let intentTypes: Set<TagType> = [.action, .event, .reminder, .question, .idea, .decision]
        let needsModel = !intentTypes.isSubset(of: existingTypes)
        if needsModel {
            tags += await modelIntentTags(for: text, skipping: existingTypes)
        }

        // Conflict resolution: Event vs Reminder on same trigger span
        tags = resolveEventReminderConflict(tags)

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

        // Negation guard — suppress action/reminder if negated
        let isNegated = matchNegation(lower)

        // Question — high detectability, auto-apply
        if let trigger = matchQuestion(lower) {
            tags.append(EntryTag(type: .question, status: .auto, confidence: 0.90, triggerText: trigger))
        }

        // Reminder — suggested (can be wrong on casual "by" usage)
        if !isNegated, let trigger = matchReminder(lower) {
            tags.append(EntryTag(type: .reminder, status: .suggested, confidence: 0.82, triggerText: trigger))
        }

        // Event — suggested (needs time + meeting verb combo)
        if let trigger = matchEvent(lower) {
            tags.append(EntryTag(type: .event, status: .suggested, confidence: 0.85, triggerText: trigger))
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
        if let trigger = matchMoney(text) {
            tags.append(EntryTag(type: .money, status: .suggested, confidence: 0.90, triggerText: trigger))
        }

        // Person — auto-apply with quick-remove affordance (PII)
        if let trigger = matchPerson(text) {
            tags.append(EntryTag(type: .person, status: .auto, confidence: 0.80, triggerText: trigger))
        }

        // Rule-based action signals (strong imperative patterns only)
        if !isNegated, let trigger = matchActionRules(lower) {
            tags.append(EntryTag(type: .action, status: .suggested, confidence: 0.75, triggerText: trigger))
        }

        return tags
    }

    // MARK: - Rule matchers

    private func matchNegation(_ lower: String) -> Bool {
        let patterns = [
            "don't remind me", "dont remind me",
            "no need to", "no need for",
            "we shouldn't", "i shouldn't",
            "not a reminder", "never mind",
            "forget it", "cancel that",
            "don't bother", "dont bother"
        ]
        return patterns.contains(where: { lower.contains($0) })
    }

    private func matchQuestion(_ lower: String) -> String? {
        if lower.contains("?") { return "?" }

        let patterns = [
            // Wh- openers
            "how do i", "how do we", "how can i", "how can we", "how should",
            "how would", "how to ", "how will",
            "what's the best", "what is the best", "what would", "what should",
            "what if i", "what if we", "what are the", "what does",
            "why is ", "why does", "why would", "why can't",
            "which one", "which is ", "which should", "which would",
            "when should", "when would", "when is the best",
            "where should", "where can i", "where do i",
            "who should", "who can ",
            // Deliberation patterns
            "should i ", "should we ", "should it ",
            "wondering if", "wondering whether", "wondering about", "wondering how",
            "not sure if", "not sure how", "not sure what", "not sure about",
            "not sure whether",
            "i don't know", "i dont know", "don't know if", "dont know how",
            "curious about", "curious if", "curious whether",
            "figure out", "figuring out", "trying to figure",
            "trying to understand", "trying to decide",
            "need to decide", "need to figure",
            "any idea ", "any ideas ", "any thoughts",
            "is there a way", "is it possible",
            "can i ", "can we ", "could i ", "could we "
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchReminder(_ lower: String) -> String? {
        let strongPatterns = [
            "remind me", "don't forget", "dont forget",
            "remember to", "remember that", "make sure to", "make sure i",
            "make sure we", "don't let me forget", "dont let me forget",
            "follow up", "follow-up", "circle back", "check in on", "check back",
            "get back to", "need to get back", "ping them", "ping him", "ping her",
            "chase up", "nudge ", "must not forget"
        ]
        if let m = firstMatch(in: lower, patterns: strongPatterns) { return m }

        // Deadline patterns
        let timeAnchors = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "tomorrow", "tonight", "today",
            "end of day", "eod", "end of week", "eow", "end of month",
            "next week", "this week", "this weekend",
            "in two days", "in a few days", "in a week", "in two weeks",
            "later today", "later this week",
            "asap", "soon", "urgently"
        ]
        for anchor in timeAnchors {
            if lower.contains("by \(anchor)") { return "by \(anchor)" }
            if lower.contains("before \(anchor)") { return "before \(anchor)" }
            if lower.contains("due \(anchor)") { return "due \(anchor)" }
            if lower.contains("due by") { return "due by" }
        }

        // "gotta X by Y" / "gotta remember"
        if lower.contains("gotta ") { return "gotta" }

        return nil
    }

    private func matchEvent(_ lower: String) -> String? {
        let meetingVerbs = [
            // Explicit scheduling
            "meeting with", "meeting at", "meeting on",
            "appointment", "appointments",
            "scheduled", "schedule a", "schedule the",
            "book a", "book the", "booked",
            // Call/sync
            "call with", "call at", "on a call",
            "sync with", "sync at",
            "hop on a call", "jump on a call", "get on a call",
            "video call", "phone call",
            // Social/in-person
            "meet ", "meeting ", "meetup",
            "catch up with", "catchup with", "catching up with",
            "session with", "session at",
            "coffee with", "grabbing coffee", "getting coffee",
            "lunch with", "grabbing lunch", "getting lunch",
            "dinner with", "grabbing dinner", "getting dinner",
            "drinks with", "grabbing drinks",
            "seeing ", "visiting ",
            "interview at", "interview with",
            "presentation at", "presentation to",
            "demo with", "demo at",
            "workshop at", "workshop with",
            "conference ", "event at"
        ]
        guard let verb = firstMatch(in: lower, patterns: meetingVerbs) else { return nil }

        // Must also contain a time reference
        let timeWords = [
            "tomorrow", "today", "tonight",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "next week", "this week", "this weekend",
            "next monday", "next tuesday", "next wednesday", "next thursday",
            "next friday", "next saturday", "next sunday",
            "at ", "am", "pm", "noon", "morning", "afternoon", "evening",
            "in the morning", "in the afternoon", "in the evening",
            "after work", "after lunch", "after school",
            "o'clock", "oclock"
        ]
        guard timeWords.contains(where: { lower.contains($0) }) else { return nil }
        return verb
    }

    private func matchReference(_ lower: String) -> String? {
        // URLs
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return "link"
        }
        // File extensions
        let extensions = [".pdf", ".doc", ".docx", ".pptx", ".xlsx", ".csv", ".txt", ".md",
                          ".ppt", ".keynote", ".pages", ".numbers", ".zip"]
        if let ext = extensions.first(where: { lower.contains($0) }) { return ext }

        // Media / article references
        let patterns = [
            "that article", "that post", "that paper", "that video", "that podcast",
            "that episode", "that book", "that thread", "that repo", "that link",
            "the article", "the paper", "the report", "the deck", "the doc",
            "the book", "the episode", "the podcast", "the video",
            "read that", "watch that", "listen to that",
            "check out", "look at that", "look up",
            "link to", "that link",
            "read this", "watch this", "listen to this",
            "send me the", "share the", "share that",
            "based on the", "according to",
            "saw this", "saw that", "found this", "found that"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchPurchase(_ lower: String) -> String? {
        // Guard figurative uses first
        let figurative = ["buy into", "buy that idea", "buy the idea", "buying into",
                          "sell the idea", "sell that", "i'm sold"]
        if figurative.contains(where: { lower.contains($0) }) { return nil }

        let patterns = [
            "buy ", "order ", "purchase ", "pick up ",
            "get more ", "get some ", "grab some ", "grab a ",
            "subscribe to", "sign up for", "add to cart", "add to list",
            "need to order", "need to buy", "need to get more", "need to pick up",
            "restock ", "reorder ", "replenish ",
            "stock up", "running low", "running out",
            "shop for", "shopping for",
            "want to get", "looking to buy", "looking to get",
            "replacement ", "spare "
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchMoney(_ text: String) -> String? {
        // Currency symbols (use original case text)
        let symbols = ["$", "£", "€", "₹", "¥"]
        if let sym = symbols.first(where: { text.contains($0) }) { return sym }

        let lower = text.lowercased()

        // Dimension/measurement guard
        let dimensionGuard = ["cm", "mm", "kg", "km", "gb", "mb", "px", "pt", "deg",
                              "ml", "mg", "oz", "lb", "ft", "in", "yd"]
        let words = lower.split(separator: " ").map(String.init)
        let hasDimensionWord = words.contains(where: { w in
            dimensionGuard.contains(where: { w.hasSuffix($0) })
        })

        // k-suffix amounts (5k, 10k, 1.5k) — only flag if not a dimension context
        if !hasDimensionWord {
            let kPattern = #"\b\d+(\.\d+)?k\b"#
            if lower.range(of: kPattern, options: .regularExpression) != nil {
                return "amount"
            }
        }

        // Indian amounts
        if lower.contains("lakh") || lower.contains("lakhs") ||
           lower.contains("crore") || lower.contains("crores") {
            return "amount"
        }

        let patterns = [
            "budget", "cost ", "costs ", "price ", "pricing",
            "payment", "invoice", "fee ", "fees", "spend ",
            "spending", "expense", "expenses", "reimburs",
            "dollars", "rupees", "euros", "pounds",
            "charge ", "charges", "charged",
            "quote ", "quoted", "estimate ", "estimated",
            "worth ", "valued at", "going rate",
            "salary", "wage", "rate per", "per hour", "per day",
            "discount", "markup", "margin"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    private func matchPerson(_ text: String) -> String? {
        // Look for capitalized name after social/action verbs
        let verbPatterns = [
            "with ", "tell ", "email ", "ask ", "call ", "meet ", "meeting ",
            "message ", "contact ", "cc ", "talk to ", "update ", "inform ",
            "remind ", "ping ", "text ", "dm ", "invite ", "introduce ",
            "catch up with ", "sync with ", "from ", "to ", "for ",
            "seeing ", "visiting ", "grabbing coffee with ", "lunch with ",
            "dinner with ", "drinks with "
        ]
        let words = text.components(separatedBy: .whitespaces)

        for (i, word) in words.enumerated() {
            let lw = word.lowercased()
            guard verbPatterns.contains(where: { lw.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }) else { continue }
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
        let patterns = [
            // Modal intention
            "need to ", "need to get", "i need to", "we need to",
            "i should ", "we should ", "you should ",
            "have to ", "has to ", "got to ", "gotta ",
            "must ", "ought to ",
            // Imperative verbs
            "send ", "call ", "write ", "draft ", "prepare ",
            "finish ", "complete ", "submit ", "review ", "approve ",
            "arrange ", "organize ", "plan ", "schedule ",
            "look into", "reach out", "follow up on",
            "sort out", "take care of", "deal with",
            "check on", "check with", "confirm ",
            "book ", "reserve ", "order ",
            "remind me to",
            // Task framing
            "next step", "next steps", "action item", "action items",
            "todo:", "to do:", "to-do:", "task:",
            "assigned to", "i'm on it", "on my list"
        ]
        return firstMatch(in: lower, patterns: patterns)
    }

    // MARK: - Conflict resolution

    /// If Event and Reminder both fired on the same trigger phrase → keep Event only.
    /// If they fired on different phrases → keep both (genuinely separate signals).
    private func resolveEventReminderConflict(_ tags: [EntryTag]) -> [EntryTag] {
        guard let eventTag = tags.first(where: { $0.type == .event }),
              let reminderTag = tags.first(where: { $0.type == .reminder }) else {
            return tags
        }

        // If trigger texts overlap or are the same → same phrase, drop Reminder
        let eventTrigger = eventTag.triggerText?.lowercased() ?? ""
        let reminderTrigger = reminderTag.triggerText?.lowercased() ?? ""

        let sameSpan = !eventTrigger.isEmpty
            && !reminderTrigger.isEmpty
            && (eventTrigger.contains(reminderTrigger) || reminderTrigger.contains(eventTrigger))

        if sameSpan {
            return tags.filter { $0.type != .reminder }
        }

        // Different triggers → both are genuine, keep both
        return tags
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
                Voice notes often lack punctuation (no question marks), so infer intent from word choice.
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
            if output.isEvent && !skipping.contains(.event) {
                tags.append(EntryTag(type: .event, status: .suggested, confidence: 0.78))
            }
            if output.isReminder && !skipping.contains(.reminder) {
                tags.append(EntryTag(type: .reminder, status: .suggested, confidence: 0.75))
            }
            if output.isQuestion && !skipping.contains(.question) {
                tags.append(EntryTag(type: .question, status: .auto, confidence: 0.80))
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
        "july", "august", "september", "october", "november", "december",
        "today", "tomorrow", "tonight", "morning", "afternoon", "evening",
        "some", "few", "all", "both", "each", "every", "any", "more", "most",
        "about", "after", "before", "during", "since", "until", "while",
        "up", "down", "out", "off", "over", "under", "again", "back", "here", "there"
    ]
}
