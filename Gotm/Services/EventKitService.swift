import Combine
import EventKit
import Foundation
import Observation

/// Service for integrating with Apple Calendar and Reminders via EventKit
@MainActor
@Observable
final class EventKitService {
    static let shared = EventKitService()
    
    private let eventStore = EKEventStore()
    
    private(set) var calendarAccessGranted = false
    private(set) var remindersAccessGranted = false
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        let remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        
        calendarAccessGranted = (calendarStatus == .fullAccess)
        remindersAccessGranted = (remindersStatus == .fullAccess)
    }
    
    /// Request calendar access
    func requestCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .fullAccess:
            calendarAccessGranted = true
            return true
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                calendarAccessGranted = granted
                return granted
            } catch {
                print("❌ [EventKit] Calendar access request failed: \(error)")
                return false
            }
        default:
            return false
        }
    }
    
    /// Request reminders access
    func requestRemindersAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        
        switch status {
        case .fullAccess:
            remindersAccessGranted = true
            return true
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                remindersAccessGranted = granted
                return granted
            } catch {
                print("❌ [EventKit] Reminders access request failed: \(error)")
                return false
            }
        default:
            return false
        }
    }
    
    /// Request both permissions at once
    func requestAllAccess() async -> (calendar: Bool, reminders: Bool) {
        async let calendar = requestCalendarAccess()
        async let reminders = requestRemindersAccess()
        return await (calendar, reminders)
    }
    
    // MARK: - Event (Calendar)
    
    /// Create a calendar event from a voice note
    /// - Parameters:
    ///   - title: Event title
    ///   - startDate: When the event starts
    ///   - endDate: When the event ends (optional, defaults to 1 hour)
    ///   - location: Optional location
    ///   - notes: Optional notes (can include transcript)
    /// - Returns: The created event identifier if successful
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil
    ) async -> String? {
        guard await requestCalendarAccess() else {
            print("⚠️ [EventKit] Calendar access not granted")
            return nil
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour
        event.location = location
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        // Add default alert 15 minutes before
        let alarm = EKAlarm(relativeOffset: -900) // 15 minutes
        event.addAlarm(alarm)
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            print("✅ [EventKit] Created event: \(title) at \(startDate)")
            return event.eventIdentifier
        } catch {
            print("❌ [EventKit] Failed to create event: \(error)")
            return nil
        }
    }
    
    /// Quick create event from transcript text (with basic date parsing)
    func createEventFromTranscript(_ transcript: String) async -> String? {
        let (title, date) = parseEventDetails(from: transcript)
        return await createEvent(
            title: title,
            startDate: date,
            notes: "From Gotm: \(transcript)"
        )
    }
    
    // MARK: - Reminder
    
    /// Create a reminder
    /// - Parameters:
    ///   - title: Reminder title
    ///   - dueDate: Optional due date with time
    ///   - listName: Optional list name (creates if doesn't exist)
    ///   - notes: Optional notes
    /// - Returns: The created reminder identifier if successful
    func createReminder(
        title: String,
        dueDate: Date? = nil,
        listName: String? = nil,
        notes: String? = nil
    ) async -> String? {
        guard await requestRemindersAccess() else {
            print("⚠️ [EventKit] Reminders access not granted")
            return nil
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            
            // Add alarm at due date
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }
        
        // Find or create the list
        if let listName = listName {
            reminder.calendar = findOrCreateList(named: listName)
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ [EventKit] Created reminder: \(title)")
            return reminder.calendarItemIdentifier
        } catch {
            print("❌ [EventKit] Failed to create reminder: \(error)")
            return nil
        }
    }
    
    /// Create an Action in the "To-Do" list (separate from general reminders)
    func createAction(_ title: String, dueDate: Date? = nil, notes: String? = nil) async -> String? {
        return await createReminder(
            title: title,
            dueDate: dueDate,
            listName: "To-Do",
            notes: notes
        )
    }
    
    /// Create a Purchase item in the Shopping list
    func createPurchase(_ item: String, notes: String? = nil) async -> String? {
        return await createReminder(
            title: item,
            listName: "Shopping",
            notes: notes
        )
    }
    
    /// Create a reminder from transcript with date parsing
    func createReminderFromTranscript(_ transcript: String) async -> String? {
        let (title, date) = parseReminderDetails(from: transcript)
        return await createReminder(
            title: title,
            dueDate: date,
            notes: "From Gotm: \(transcript)"
        )
    }
    
    // MARK: - Helper Methods
    
    private func findOrCreateList(named name: String) -> EKCalendar? {
        // First try to find existing list
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }
        
        // Create new list
        let newList = EKCalendar(for: .reminder, eventStore: eventStore)
        newList.title = name
        
        // Find a source to save to
        if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            newList.source = localSource
        } else if let calDAVSource = eventStore.sources.first(where: { $0.sourceType == .calDAV }) {
            newList.source = calDAVSource
        } else {
            newList.source = eventStore.defaultCalendarForNewReminders()?.source
        }
        
        do {
            try eventStore.saveCalendar(newList, commit: true)
            print("✅ [EventKit] Created list: \(name)")
            return newList
        } catch {
            print("❌ [EventKit] Failed to create list: \(error)")
            return eventStore.defaultCalendarForNewReminders()
        }
    }
    
    // MARK: - Date Parsing (Basic)
    
    /// Parse event title and date from transcript
    /// Returns (title, date) - date defaults to tomorrow if no date found
    /// Example: "Meeting with Sarah tomorrow at 3pm" -> ("Meeting with Sarah", tomorrow at 3pm)
    func parseEventDetails(from transcript: String) -> (String, Date) {
        let lower = transcript.lowercased()
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        
        // Extract clean event title using AI-like parsing
        var title = extractCleanEventTitle(from: transcript)
        
        // Extract time first (to remove from title later)
        var hour = 9
        var hasTime = false
        
        // Check for specific times like "3pm", "3 pm", "15:00"
        let timePattern = #"(\d+)(?::(\d+))?\s*(am|pm|a\.m\.|p\.m\.)?"#
        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive) {
            let range = NSRange(title.startIndex..., in: title)
            if let match = regex.firstMatch(in: title, options: [], range: range) {
                if let hourRange = Range(match.range(at: 1), in: title),
                   let h = Int(title[hourRange]) {
                    var extractedHour = h
                    // Check for am/pm
                    if match.range(at: 3).location != NSNotFound,
                       let periodRange = Range(match.range(at: 3), in: title) {
                        let period = title[periodRange].lowercased()
                        if period.contains("p") && extractedHour != 12 {
                            extractedHour += 12
                        } else if period.contains("a") && extractedHour == 12 {
                            extractedHour = 0
                        }
                    }
                    hour = extractedHour
                    hasTime = true
                    
                    // Remove the time from title
                    if let fullMatchRange = Range(match.range, in: title) {
                        title.removeSubrange(fullMatchRange)
                    }
                }
            }
        }
        
        // If no specific time found, check for keywords
        if !hasTime {
            if lower.contains("afternoon") || lower.contains("evening") {
                hour = 15 // 3 PM
                title = title.replacingOccurrences(of: "afternoon", with: "", options: .caseInsensitive)
                title = title.replacingOccurrences(of: "evening", with: "", options: .caseInsensitive)
            } else if lower.contains("morning") {
                hour = 9
                title = title.replacingOccurrences(of: "morning", with: "", options: .caseInsensitive)
            } else if lower.contains("noon") {
                hour = 12
                title = title.replacingOccurrences(of: "noon", with: "", options: .caseInsensitive)
            }
        }
        
        // Check for "tomorrow" and set date
        if lower.contains("tomorrow") {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
                dateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            }
            title = title.replacingOccurrences(of: "tomorrow", with: "", options: .caseInsensitive)
        }
        // Check for day names
        else {
            let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
            for (index, day) in days.enumerated() {
                if lower.contains(day) {
                    let weekday = index + 2 // Monday = 2 in Calendar
                    if let targetDate = nextWeekday(weekday, from: Date()) {
                        dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
                    }
                    title = title.replacingOccurrences(of: day, with: "", options: .caseInsensitive)
                    break
                }
            }
        }
        
        dateComponents.hour = hour
        dateComponents.minute = 0
        
        let finalDate = calendar.date(from: dateComponents) ?? Date()
        
        // Clean up title - remove all time references
        title = cleanTimeReferences(from: title)
        
        print("📅 [Parse] '\(transcript)' -> Title: '\(title)', Date: \(finalDate)")
        
        return (title, finalDate)
    }
    
    /// Extracts a clean, concise event title from natural language
    /// Example: "I need to speak to Sarah, I need to get on a meeting with her" -> "Meeting with Sarah"
    private func extractCleanEventTitle(from transcript: String) -> String {
        let lower = transcript.lowercased()
        
        // Step 1: Remove all filler phrases and intentions
        var cleaned = transcript
        let fillerPatterns = [
            "i need to ", "i have to ", "i must ", "i should ", "i gotta ", "i want to ",
            "we need to ", "we have to ", "we must ", "we should ", "we gotta ", "we want to ",
            "need to ", "have to ", "must ", "should ", "gotta ", "got to ",
            "i'm going to ", "im going to ", "i am going to ",
            "i would like to ", "i'd like to ", "i wanna ",
            "let's ", "lets ", "let us ",
            "i will ", "ill ", "i'll ", "we will ", "we'll ",
            "can you ", "could you ", "would you ",
            "remind me to ", "remind me ",
            "don't forget to ", "dont forget to ",
            "make sure to ", "make sure i ", "make sure we ",
            "try to ", "try and ",
            "planning to ", "planning on ",
            "thinking about ", "thinking of ",
            "looking to ", "looking forward to ",
            "hoping to ", "hope to ",
            "supposed to ", "meant to ",
            "i was thinking ", "i thought ",
            "maybe ", "perhaps ", "possibly ",
            "just ", "simply ", "basically ",
            "actually ", "really ", "definitely ",
            "probably ", "likely ", "maybe ",
            "kind of ", "sort of ", "like ",
            "you know ", "i mean ", "i guess ",
            "basically ", "literally ", "honestly "
        ]
        
        for pattern in fillerPatterns {
            if lower.hasPrefix(pattern) {
                cleaned = String(cleaned.dropFirst(pattern.count))
                break
            }
        }
        
        // Step 2: Detect meeting type and extract person
        let meetingTypes = [
            (keywords: ["meeting", "meet", "sync", "catch up", "catch-up"], type: "Meeting"),
            (keywords: ["call", "phone call", "video call", "zoom", "teams"], type: "Call"),
            (keywords: ["speak", "speaking", "talk", "talking", "chat", "chatting"], type: "Talk"),
            (keywords: ["interview", "interviewing"], type: "Interview"),
            (keywords: ["review", "reviewing"], type: "Review"),
            (keywords: ["presentation", "presenting", "demo"], type: "Presentation"),
            (keywords: ["workshop", "session"], type: "Workshop"),
            (keywords: ["appointment", "consultation"], type: "Appointment"),
            (keywords: ["conference", "conferencing"], type: "Conference"),
            (keywords: ["standup", "stand-up", "daily standup"], type: "Standup"),
            (keywords: ["1:1", "one on one", "one-on-one", "1 on 1"], type: "1:1"),
            (keywords: ["brainstorm", "brainstorming"], type: "Brainstorm"),
            (keywords: ["lunch", "dinner", "coffee", "drinks"], type: "Meeting")
        ]
        
        var detectedType: String? = nil
        for (keywords, type) in meetingTypes {
            if keywords.contains(where: { lower.contains($0) }) {
                detectedType = type
                break
            }
        }
        
        // Step 3: Extract person name or group/team name
        var personName: String? = nil
        
        // Pattern: "with [Name/Group]" - try to capture multi-word names too
        let namePatterns = [
            #"with\s+([A-Z][a-zA-Z\s]*?)(?:\s+(?:on|at|tomorrow|today|tonight|this|next|about|regarding|for|to|$))"#,  // "with Sarah tomorrow" -> "Sarah"
            #"with\s+(\w+)"#,  // Simple "with Sarah"
            #"to\s+(\w+)"#,    // "speak to John"
            #"and\s+(\w+)"#,   // "meeting with Sarah and John"
            #"from\s+(\w+)"#,  // "call from Mom"
            #"for\s+([A-Z][a-zA-Z\s]*?)(?:\s+(?:on|at|tomorrow|today|tonight|this|next|about|regarding|with|to|$))"#  // "for the team tomorrow" -> "the team"
        ]
        
        for pattern in namePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                if let match = regex.firstMatch(in: cleaned, options: [], range: range) {
                    if let nameRange = Range(match.range(at: 1), in: cleaned) {
                        let name = String(cleaned[nameRange]).trimmingCharacters(in: .whitespaces)
                        // Filter out common non-name words (but allow team, group, etc.)
                        let nonNames = ["the", "a", "an", "my", "our", "his", "her", "their", "this", "that", "these", "those", "some", "any", "all", "both", "each", "every", "another", "other", "such", "what", "which", "who", "whom", "whose", "when", "where", "why", "how", "whether", "either", "neither", "both", "few", "little", "less", "least", "many", "much", "more", "most", "several", "enough", "own", "same", "different", "former", "latter", "last", "next", "first", "second", "third", "me", "you", "him", "them", "us", "it", "us", "call", "talk", "her", "him", "them", "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "now", "later", "soon", "am", "pm"]
                        // Allow words like "team", "group", "company", "client", "customer"
                        let allowedWords = ["team", "group", "company", "client", "customers", "manager", "boss", "client", "vendor", "partner", "partners", "stakeholders", "board", "committee", "department", "staff", "crew", "squad", "unit", "division"]
                        let nameLower = name.lowercased()
                        if (allowedWords.contains(nameLower) || !nonNames.contains(nameLower)) && name.count > 1 {
                            personName = name
                            break
                        }
                    }
                }
            }
        }
        
        // Step 4: Build clean title
        var finalTitle: String
        
        if let type = detectedType, let person = personName {
            // "Meeting with Sarah"
            finalTitle = "\(type) with \(person)"
        } else if let type = detectedType {
            // Just "Meeting" if no person found
            finalTitle = type
        } else if let person = personName {
            // Just "Sarah" if no meeting type but person found
            finalTitle = person
        } else {
            // Fallback: clean up the original and use it
            finalTitle = cleanTimeReferences(from: cleaned)
        }
        
        return finalTitle
    }
    
    /// Removes all time references from text to create a clean title
    /// Example: "Team Sync at 2 PM tomorrow" -> "Team Sync"
    private func cleanTimeReferences(from text: String) -> String {
        var cleaned = text
        
        // Remove time patterns: "2 PM", "3pm", "14:00", "2:30pm", etc.
        let timePatterns = [
            #"\d{1,2}:\d{2}\s*(am|pm|a\.m\.|p\.m\.)?"#,  // 2:30pm, 14:00
            #"\d{1,2}\s*(am|pm|a\.m\.|p\.m\.)"#,         // 2 pm, 3PM
        ]
        
        for pattern in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
            }
        }
        
        // Remove time-related words and prepositions
        let timeWords = [
            "tomorrow", "today", "tonight", "yesterday",
            "morning", "afternoon", "evening", "night", "noon", "midnight",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "next week", "this week", "last week",
            "at ", "on ", "by ", "around ", "about ", "approximately ",
            "at", "on", "by"  // without space as fallback
        ]
        
        for word in timeWords {
            cleaned = cleaned.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        
        // Clean up extra spaces and punctuation
        cleaned = cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "   ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? text : cleaned
    }
    
    /// Parse reminder title and date from transcript
    /// Example: "Remind me to buy milk tomorrow" -> ("Buy milk", tomorrow)
    func parseReminderDetails(from transcript: String) -> (String, Date?) {
        let lower = transcript.lowercased()
        var date: Date? = nil
        var title = transcript
        let calendar = Calendar.current
        
        // Step 1: Extract date FIRST (before modifying title)
        if lower.contains("tomorrow") {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.day! += 1
            components.hour = 9 // Default to 9 AM
            components.minute = 0
            date = calendar.date(from: components)
        } else if lower.contains("tonight") {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 20 // 8 PM
            components.minute = 0
            date = calendar.date(from: components)
        } else if lower.contains("today") {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 18 // 6 PM
            components.minute = 0
            date = calendar.date(from: components)
        }
        
        // Step 2: Remove reminder prefixes (comprehensive list)
        let prefixes = [
            "remind me to ", "remind me ",
            "don't forget to ", "dont forget to ",
            "remember to ", "remember that ",
            "make sure to ", "make sure i ", "make sure we ",
            "don't let me forget to ", "dont let me forget to ",
            "i need to remember to ", "i must remember to ",
            "i need to ", "need to "
        ]
        
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                break
            }
        }
        
        // Step 3: Remove time words from title (we already extracted the date)
        let timeWords = ["tomorrow", "tonight", "today"]
        for word in timeWords {
            title = title.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        
        // Step 4: Clean up
        title = title
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 5: Capitalize
        if !title.isEmpty {
            title = title.prefix(1).uppercased() + title.dropFirst()
        }
        
        // Step 6: If empty, return original
        if title.isEmpty {
            title = transcript
        }
        
        print("🔔 [Parse] '\(transcript)' -> Title: '\(title)', Date: \(date?.description ?? "nil")")
        
        return (title, date)
    }
    
    private func nextWeekday(_ weekday: Int, from date: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = weekday
        
        if let targetDate = calendar.date(from: components),
           targetDate > date {
            return targetDate
        }
        
        // If already passed this week, get next week
        components.weekOfYear! += 1
        return calendar.date(from: components)
    }
}

// MARK: - Errors

enum EventKitError: LocalizedError {
    case accessDenied
    case eventCreationFailed
    case reminderCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Please allow access to Calendar and Reminders in Settings"
        case .eventCreationFailed:
            return "Could not create calendar event"
        case .reminderCreationFailed:
            return "Could not create reminder"
        }
    }
}
