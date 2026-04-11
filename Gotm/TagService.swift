import Foundation

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

        // Conflict resolution: remove duplicate/overlapping tags
        tags = resolveConflicts(tags)

        // Deduplicate (keep highest confidence per type) and sort by feed priority
        var best: [TagType: EntryTag] = [:]
        for tag in tags {
            if let existing = best[tag.type] {
                if tag.confidence > existing.confidence { best[tag.type] = tag }
            } else {
                best[tag.type] = tag
            }
        }

        var result = best.values.sorted { $0.type.feedPriority < $1.type.feedPriority }

        // Fallback — every entry gets at least a Note tag
        if result.isEmpty {
            result = [EntryTag(type: .note, status: .auto, confidence: 1.0)]
        }

        return result
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

        // Reminder — auto-apply if strong signal, suggested if weaker
        if !isNegated, let trigger = matchReminder(lower) {
            let confidence = isStrongReminder(lower) ? 0.88 : 0.78
            let status: TagStatus = confidence >= 0.85 ? .auto : .suggested
            tags.append(EntryTag(type: .reminder, status: status, confidence: confidence, triggerText: trigger))
        }

        // Event — auto-apply if strong signal, suggested if weaker  
        if let trigger = matchEvent(lower) {
            let confidence = isStrongEvent(lower) ? 0.88 : 0.78
            let status: TagStatus = confidence >= 0.85 ? .auto : .suggested
            tags.append(EntryTag(type: .event, status: status, confidence: confidence, triggerText: trigger))
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

        // Person — handled entirely by AI model (rule-based detection is too unreliable:
        // it can't distinguish human names from bands, places, brands, etc.)

        // Rule-based action signals
        if !isNegated, let trigger = matchActionRules(lower) {
            let confidence = isStrongAction(lower) ? 0.85 : 0.75
            let status: TagStatus = confidence >= 0.85 ? .auto : .suggested
            tags.append(EntryTag(type: .action, status: status, confidence: confidence, triggerText: trigger))
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
        // Guard: exclude idea statements that might trigger question patterns
        let ideaIndicators = [
            "i have an idea", "i have a idea", "my idea is", "idea for",
            "idea: ", "here's an idea", "here is an idea",
            "another idea", "new idea", "app idea"
        ]
        if ideaIndicators.contains(where: { lower.contains($0) }) { return nil }
        
        // No bare "?" check — a single question mark doesn't mean the note is a question.
        // The AI model handles question detection with full context.
        // Rules only fire on unambiguous question structures.
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

        // Future time + intention = implicit reminder
        // e.g. "tomorrow I need to plan a visit" / "I should call next week"
        let futureTimes = [
            "tomorrow", "tonight", "next week", "this weekend",
            "next monday", "next tuesday", "next wednesday", "next thursday",
            "next friday", "next saturday", "next sunday",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]
        let intentionWords = [
            "need to", "have to", "got to", "should ", "plan to",
            "planning to", "want to", "thinking of", "going to"
        ]
        for time in futureTimes {
            guard lower.contains(time) else { continue }
            for intention in intentionWords {
                if lower.contains(intention) { return time }
            }
        }

        return nil
    }

    private func matchEvent(_ lower: String) -> String? {
        // Guard: exclude past tense markers - events are future-oriented
        let pastTenseIndicators = [
            " went ", "went well", "went badly", " was ", "were ", " had ",
            "happened", "occurred", "took place", "finished", "completed",
            "yesterday", "last week", "last month", "last monday", "last tuesday",
            "already ", "just finished", "just completed", "recently"
        ]
        if pastTenseIndicators.contains(where: { lower.contains($0) }) { return nil }
        
        // Guard: exclude retrospective phrases
        let retrospectivePhrases = [
            "the meeting with", "my meeting with", "our meeting with",
            "the call with", "my call with", "our call with",
            "catch up with", "catching up with" // Past tense usage
        ]
        // Only block if it looks like a past reference (no future time words)
        let futureTimeWords = ["tomorrow", "next ", "upcoming", "later", "soon"]
        let hasFutureMarker = futureTimeWords.contains(where: { lower.contains($0) })
        if !hasFutureMarker && retrospectivePhrases.contains(where: { lower.contains($0) }) {
            return nil
        }
        
        let meetingVerbs = [
            // Explicit scheduling
            "meeting with", "meeting at", "meeting on",
            "appointment", "appointments",
            "schedule a", "schedule the",
            "book a", "book the",
            // Call/sync
            "call with", "call at", "on a call",
            "sync with", "sync at",
            "hop on a call", "jump on a call", "get on a call",
            "video call", "phone call",
            // Social/in-person
            "meet ", "meeting ", "meetup",
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
        // File extensions — require a non-alpha character after the extension so
        // ".doc" doesn't match "doctor", ".md" doesn't match "made", etc.
        let extensions = [".pdf", ".doc", ".docx", ".pptx", ".xlsx", ".csv", ".txt", ".md",
                          ".ppt", ".keynote", ".pages", ".numbers", ".zip"]
        for ext in extensions {
            if let range = lower.range(of: ext) {
                let after = lower[range.upperBound...]
                if after.isEmpty || !after.first!.isLetter {
                    return ext
                }
            }
        }

        // Longer patterns are unambiguous — plain contains() is fine
        let unambiguousPatterns = [
            "that article", "that post", "that paper", "that video", "that podcast",
            "that episode", "that book", "that thread", "that repo", "that link",
            "the article", "the paper", "the report", "the deck",
            "the book", "the episode", "the podcast", "the video",
            "read that", "watch that", "listen to that",
            "look at that", "look up",
            "link to", "that link",
            "read this", "watch this", "listen to this",
            "send me the", "share the", "share that",
            "based on the", "according to",
            "saw this", "saw that", "found this", "found that"
        ]
        if let m = firstMatch(in: lower, patterns: unambiguousPatterns) { return m }

        // Short ambiguous patterns — require word boundary after the match
        // so "the doc" matches "the doc." or "the doc " but not "the doctor"
        let boundaryPatterns = ["the doc", "check out"]
        for pattern in boundaryPatterns {
            if let range = lower.range(of: pattern) {
                let after = lower[range.upperBound...]
                if after.isEmpty || !after.first!.isLetter {
                    return pattern
                }
            }
        }

        return nil
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

    // matchPerson removed — person detection is handled entirely by the AI model
    // which can distinguish human names from bands, places, and brands.

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

    /// Resolves conflicts between similar tag types to reduce false positives.
    /// Priority: Purchase > Reminder > Action (for buy-related tasks)
    ///           Reminder > Action (for general tasks)
    ///           Event stands alone
    private func resolveConflicts(_ tags: [EntryTag]) -> [EntryTag] {
        var result = tags
        
        // 1. Event vs Reminder: Event wins if same trigger
        result = resolveEventReminderConflict(result)
        
        // 2. Purchase vs Reminder vs Action: Purchase wins for buy-related
        result = resolvePurchaseReminderActionConflict(result)
        
        return result
    }
    
    /// If Event and Reminder both fired on the same trigger phrase → keep Event only.
    private func resolveEventReminderConflict(_ tags: [EntryTag]) -> [EntryTag] {
        guard tags.contains(where: { $0.type == .event }),
              tags.contains(where: { $0.type == .reminder }) else {
            return tags
        }
        // Event is more specific - drop Reminder when both exist
        return tags.filter { $0.type != .reminder }
    }
    
    /// Resolves conflicts between Purchase, Reminder, and Action.
    /// Logic:
    /// - If Purchase exists (buy/order/purchase keywords) → drop Reminder and Action
    /// - Else if Reminder exists (remind me/don't forget) → drop Action
    /// - Else keep Action
    private func resolvePurchaseReminderActionConflict(_ tags: [EntryTag]) -> [EntryTag] {
        let hasPurchase = tags.contains(where: { $0.type == .purchase })
        let hasReminder = tags.contains(where: { $0.type == .reminder })
        _ = tags.contains(where: { $0.type == .action })
        
        // Purchase is most specific for buy-related tasks
        if hasPurchase {
            // Keep Purchase, drop Reminder and Action
            return tags.filter { $0.type != .reminder && $0.type != .action }
        }
        
        // Reminder is next most specific
        if hasReminder {
            // Keep Reminder, drop Action
            return tags.filter { $0.type != .action }
        }
        
        return tags
    }

    // MARK: - Helpers

    private func firstMatch(in text: String, patterns: [String]) -> String? {
        patterns.first(where: { text.contains($0) })
    }
    
    // MARK: - Confidence Helpers
    
    private func isStrongReminder(_ lower: String) -> Bool {
        let strongPatterns = [
            "remind me", "don't forget", "dont forget", "remember to",
            "make sure to", "don't let me forget", "follow up"
        ]
        return strongPatterns.contains(where: { lower.contains($0) })
    }
    
    private func isStrongEvent(_ lower: String) -> Bool {
        // Strong signals: explicit meeting verbs with specific time
        let hasSpecificTime = [
            "at ", "am", "pm", "noon", "o'clock", "oclock"
        ].contains(where: { lower.contains($0) })
        
        let strongVerbs = [
            "meeting with", "appointment", "scheduled", "booked"
        ].contains(where: { lower.contains($0) })
        
        return hasSpecificTime && strongVerbs
    }
    
    private func isStrongAction(_ lower: String) -> Bool {
        let strongPatterns = [
            "need to ", "have to ", "must ", "remind me to"
        ]
        return strongPatterns.contains(where: { lower.contains($0) })
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
