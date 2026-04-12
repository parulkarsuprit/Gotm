import Combine
import SwiftUI
import Observation

/// Represents the state of a tag action
enum TagActionState: Equatable {
    case idle
    case processing
    case completed(String) // Stores the created item identifier
    case failed(String)
}

/// Handles actions for each tag type by routing to appropriate service
@MainActor
@Observable
final class TagActionHandler {
    static let shared = TagActionHandler()
    
    let eventKit = EventKitService.shared
    let emailService = EmailService.shared
    let notesService = NotesService.shared
    
    // Global toast state
    var showSuccessToast = false
    var successMessage = ""
    var showErrorToast = false
    var errorMessage = ""
    
    // Track processing and completed states per entry-tag combination
    private var processingEntries: Set<String> = [] // "entryID-tagType"
    private var completedActions: [String: String] = [:] // "entryID-tagType" -> createdItemID
    
    private init() {}
    
    // MARK: - State Management
    
    private func key(for entryID: UUID, tagType: TagType) -> String {
        "\(entryID.uuidString)-\(tagType.rawValue)"
    }
    
    func state(for entryID: UUID, tagType: TagType) -> TagActionState {
        let k = key(for: entryID, tagType: tagType)
        if processingEntries.contains(k) {
            return .processing
        }
        if let itemID = completedActions[k] {
            return .completed(itemID)
        }
        return .idle
    }
    
    func isProcessing(entryID: UUID, tagType: TagType) -> Bool {
        state(for: entryID, tagType: tagType) == .processing
    }
    
    func isCompleted(entryID: UUID, tagType: TagType) -> Bool {
        if case .completed = state(for: entryID, tagType: tagType) {
            return true
        }
        return false
    }
    
    // MARK: - Action Execution
    
    func executeAction(for tag: EntryTag, entry: RecordingEntry) {
        let k = key(for: entry.id, tagType: tag.type)
        
        // Check current state
        switch state(for: entry.id, tagType: tag.type) {
        case .processing:
            return // Already processing, ignore
        case .completed:
            // Already added - show feedback and offer to remove
            showSuccess("Already added to \(destinationName(for: tag.type))")
            return
        case .failed:
            // Retry - remove from failed state
            break
        case .idle:
            break
        }
        
        // Mark as processing
        processingEntries.insert(k)
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        switch tag.type {
        case .event:
            handleEventAction(entry: entry, tag: tag, key: k)
        case .reminder:
            handleReminderAction(entry: entry, tag: tag, key: k)
        case .action:
            handleActionTask(entry: entry, tag: tag, key: k)
        case .purchase:
            handlePurchaseAction(entry: entry, tag: tag, key: k)
        case .reference, .note, .idea, .decision, .question, .person, .money:
            handleShareAction(entry: entry)
            processingEntries.remove(k)
        }
    }
    
    // MARK: - Individual Handlers
    
    private func handleEventAction(entry: RecordingEntry, tag: EntryTag, key: String) {
        Task {
            defer { processingEntries.remove(key) }
            
            // ALWAYS use full transcript for proper context extraction
            let transcript = entry.transcript ?? entry.name
            let (title, date) = eventKit.parseEventDetails(from: transcript)
            
            print("📅 [Event] Creating: '\(title)' at \(date)")
            
            if let eventId = await eventKit.createEvent(
                title: title,
                startDate: date,
                notes: "From Gotm: \(transcript)"
            ) {
                completedActions[key] = eventId
                showSuccess("Added to Calendar")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                print("✅ [Event] Created with ID: \(eventId)")
            } else {
                showError("Failed to add to Calendar")
                print("❌ [Event] Failed to create")
            }
        }
    }
    
    private func handleReminderAction(entry: RecordingEntry, tag: EntryTag, key: String) {
        Task {
            defer { processingEntries.remove(key) }
            
            // ALWAYS use full transcript for proper context extraction
            let transcript = entry.transcript ?? entry.name
            let title = extractReminderTitle(from: transcript)
            let date = extractDate(from: transcript)
            
            print("🔔 [Reminder] Creating: '\(title)' due: \(date?.description ?? "nil")")
            
            if let reminderId = await eventKit.createReminder(
                title: title,
                dueDate: date,
                notes: "From Gotm"
            ) {
                completedActions[key] = reminderId
                showSuccess("Added to Reminders")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                print("✅ [Reminder] Created with ID: \(reminderId)")
            } else {
                showError("Failed to add to Reminders")
                print("❌ [Reminder] Failed to create")
            }
        }
    }
    
    private func handleActionTask(entry: RecordingEntry, tag: EntryTag, key: String) {
        Task {
            defer { processingEntries.remove(key) }
            
            // ALWAYS use full transcript for proper context extraction
            let transcript = entry.transcript ?? entry.name
            let title = extractActionTitle(from: transcript)
            
            print("⚡ [Action] Creating: '\(title)'")
            
            if let reminderId = await eventKit.createAction(title) {
                completedActions[key] = reminderId
                showSuccess("Added to To-Do List")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                print("✅ [Action] Created with ID: \(reminderId)")
            } else {
                showError("Failed to add to To-Do List")
                print("❌ [Action] Failed to create")
            }
        }
    }
    
    private func handlePurchaseAction(entry: RecordingEntry, tag: EntryTag, key: String) {
        Task {
            defer { processingEntries.remove(key) }
            
            // ALWAYS use full transcript for proper context extraction
            let transcript = entry.transcript ?? entry.name
            let title = extractPurchaseTitle(from: transcript)
            
            print("🛒 [Purchase] Creating: '\(title)'")
            
            if let reminderId = await eventKit.createPurchase(title) {
                completedActions[key] = reminderId
                showSuccess("Added to Shopping List")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                showError("Failed to add to Shopping List")
            }
        }
    }
    
    private func handleShareAction(entry: RecordingEntry) {
        notesService.shareEntry(entry)
    }
    
    // MARK: - Text Extraction
    
    /// Extracts the core reminder task from text like "Remind me to buy milk tomorrow"
    /// Result: "Buy milk tomorrow"
    private func extractReminderTitle(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        
        // Step 1: Remove ALL reminder prefixes (more comprehensive)
        let prefixes = [
            // Core reminder phrases
            "remind me to ", "remind me ",
            "don't forget to ", "dont forget to ",
            "remember to ", "remember that ",
            "make sure to ", "make sure i ", "make sure we ",
            "don't let me forget to ", "dont let me forget to ",
            "i need to remember to ", "i must remember to ",
            // Action phrases that become reminders (when no other tag type)
            "i need to ", "we need to ", "need to ",
            "i should ", "we should ", "should ",
            "i have to ", "we have to ", "have to ",
            "i must ", "we must ", "must ",
            "i gotta ", "gotta ", "got to ",
            // Additional intention phrases
            "i will ", "i'll ", "we will ", "we'll ",
            "i want to ", "we want to ", "wanna ",
            "i'm gonna ", "im gonna ", "i am gonna ", "gonna "
        ]
        
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        
        // Step 2: Clean up any remaining leading punctuation or spaces
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 3: Remove filler words from middle of text
        let fillerWords = ["basically", "literally", "actually", "just", "simply", "um", "uh"]
        for filler in fillerWords {
            result = result.replacingOccurrences(of: " \(filler) ", with: " ", options: .caseInsensitive)
        }
        
        // Step 4: Keep time context but clean it up
        // Remove specific times like "at 2 PM" but keep "tomorrow"
        let timePatterns = [
            #"at\s+\d{1,2}:\d{2}\s*(am|pm)?"#,
            #"at\s+\d{1,2}\s*(am|pm)"#,
            #"around\s+\d{1,2}\s*(am|pm)?"#
        ]
        for pattern in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        
        // Step 5: Clean up extra spaces
        result = result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 6: Capitalize first letter
        if !result.isEmpty {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        
        // Step 7: If empty after stripping, return original
        return result.isEmpty ? text : result
    }
    
    /// Extracts the core action from text like "I need to call John about the project"
    /// Result: "Call John about the project"
    private func extractActionTitle(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        
        // Step 1: Remove action prefixes (comprehensive)
        let prefixes = [
            "i need to ", "we need to ", "need to ",
            "i should ", "we should ", "you should ", "should ",
            "i have to ", "we have to ", "have to ",
            "i got to ", "got to ", "gotta ",
            "i must ", "we must ", "must ",
            "i ought to ", "ought to ",
            "i will ", "i'll ", "we will ", "we'll ",
            "i want to ", "we want to ", "wanna ",
            "i'm gonna ", "im gonna ", "i am gonna ", "gonna ",
            "i'm going to ", "im going to ", "i am going to ",
            "i'd like to ", "i would like to ", "i'd love to ",
            "let me ", "let us ", "let's "
        ]
        
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        
        // Step 2: Remove filler words
        let fillerWords = ["basically", "literally", "actually", "just", "simply", "um", "uh", "like", "you know"]
        for filler in fillerWords {
            result = result.replacingOccurrences(of: " \(filler) ", with: " ", options: .caseInsensitive)
            result = result.replacingOccurrences(of: "\(filler) ", with: "", options: .caseInsensitive)
        }
        
        // Step 3: Clean up
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 4: Capitalize first letter
        if !result.isEmpty {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        
        // Step 5: If empty, return original
        return result.isEmpty ? text : result
    }
    
    /// Extracts the purchase item from text like "I need to buy milk and eggs tomorrow"
    /// Result: "Milk and eggs tomorrow"
    private func extractPurchaseTitle(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        
        // Step 1: Remove purchase prefixes
        let prefixes = [
            "i need to buy ", "i need to get ", "i need to order ", "i need to purchase ",
            "we need to buy ", "we need to get ", "we need to order ",
            "need to buy ", "need to get ", "need to order ", "need to purchase ",
            "i want to buy ", "i want to get ", "i want to order ",
            "i should buy ", "i should get ", "i should order ",
            "i think i need to buy ", "i think i need to get ",
            "i think ", "i feel like ",
            "buy ", "get ", "order ", "purchase ", "pick up "
        ]
        
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        
        // Step 2: Remove "X are over" patterns
        let overPatterns = [
            "coffee beans are over. ", "coffee beans are over ",
            "milk is over. ", "milk is over ",
            "we are out of ", "i'm out of ", "im out of ",
            "running low on ", "running out of ", "need more "
        ]
        let resultLower = result.lowercased()
        for pattern in overPatterns {
            if resultLower.hasPrefix(pattern) {
                result = String(result.dropFirst(pattern.count))
                break
            }
        }
        
        // Step 3: Clean up
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 4: Capitalize first letter
        if !result.isEmpty {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        
        // Step 5: If empty, return original
        return result.isEmpty ? text : result
    }
    
    /// Extracts date from text
    private func extractDate(from text: String) -> Date? {
        let lower = text.lowercased()
        let calendar = Calendar.current
        
        if lower.contains("tomorrow") {
            // Set to 9 AM tomorrow by default
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.day! += 1
            components.hour = 9
            components.minute = 0
            return calendar.date(from: components)
        } else if lower.contains("tonight") {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 20
            components.minute = 0
            return calendar.date(from: components)
        } else if lower.contains("today") {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 18
            components.minute = 0
            return calendar.date(from: components)
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func destinationName(for tagType: TagType) -> String {
        switch tagType {
        case .event: return "Calendar"
        case .reminder: return "Reminders"
        case .action: return "To-Do List"
        case .purchase: return "Shopping List"
        default: return "Notes"
        }
    }
    
    func canExecuteAction(for tagType: TagType) -> Bool {
        switch tagType {
        case .event, .reminder, .action, .purchase,
             .reference, .note, .idea, .decision, .question, .person, .money:
            return true
        }
    }
    
    // MARK: - Feedback
    
    private func showSuccess(_ message: String) {
        successMessage = message
        showSuccessToast = true
        showErrorToast = false
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSuccessToast = false
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showErrorToast = true
        showSuccessToast = false
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showErrorToast = false
        }
    }
}

// MARK: - View Modifier

struct TagActionOverlayModifier: ViewModifier {
    @State private var handler = TagActionHandler.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Success Toast - centered on screen, on top of everything
            VStack {
                if handler.showSuccessToast {
                    ToastView(message: handler.successMessage, type: .success)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                if handler.showErrorToast {
                    ToastView(message: handler.errorMessage, type: .error)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                Spacer()
            }
            .padding(.top, 60)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: handler.showSuccessToast)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: handler.showErrorToast)
            .allowsHitTesting(false) // Let taps pass through
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success
        case error
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
                .font(.title3)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 30)
    }
}

// MARK: - Legacy Modifier for Sheets

struct TagActionSheetModifier: ViewModifier {
    private let handler = TagActionHandler.shared
    private let emailService = EmailService.shared
    private let notesService = NotesService.shared
    
    @State private var shareCoordinator: ShareSheetCoordinator?
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Bindable(emailService).isShowingMailCompose) {
                if let mailData = emailService.mailData {
                    MailComposeView(
                        isShowing: Bindable(emailService).isShowingMailCompose,
                        mailData: mailData
                    )
                }
            }
            // Use a coordinator to present share sheet directly from window
            .onChange(of: notesService.isShowingShareSheet) { _, isShowing in
                if isShowing {
                    shareCoordinator = ShareSheetCoordinator(
                        isPresented: Bindable(notesService).isShowingShareSheet,
                        items: notesService.shareItems,
                        subject: notesService.shareSubject
                    )
                    shareCoordinator?.present()
                } else {
                    shareCoordinator?.dismiss()
                    shareCoordinator = nil
                }
            }
    }
}

/// Coordinator that presents share sheet directly without SwiftUI sheet wrapper
@MainActor
class ShareSheetCoordinator: NSObject {
    private var isPresented: Binding<Bool>
    private let items: [Any]
    private let subject: String?
    private weak var activityVC: UIActivityViewController?
    
    init(isPresented: Binding<Bool>, items: [Any], subject: String?) {
        self.isPresented = isPresented
        self.items = items
        self.subject = subject
        super.init()
    }
    
    func present() {
        guard activityVC == nil else { return }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let subject = subject {
            activityVC.setValue(subject, forKey: "subject")
        }
        
        activityVC.excludedActivityTypes = [.assignToContact, .addToReadingList]
        
        activityVC.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.isPresented.wrappedValue = false
        }
        
        activityVC.presentationController?.delegate = self
        
        self.activityVC = activityVC
        
        // Present from top view controller
        if let topVC = findTopViewController() {
            // For iPad, configure popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topVC.present(activityVC, animated: true)
        }
    }
    
    func dismiss() {
        activityVC?.dismiss(animated: true)
        activityVC = nil
    }
    
    private func findTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        var topVC = window.rootViewController
        while let presented = topVC?.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

extension ShareSheetCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresented.wrappedValue = false
    }
}

struct ToastOverlay: View {
    @State private var handler = TagActionHandler.shared
    
    var body: some View {
        VStack {
            if handler.showSuccessToast {
                ToastView(message: handler.successMessage, type: .success)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            if handler.showErrorToast {
                ToastView(message: handler.errorMessage, type: .error)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            Spacer()
        }
        .padding(.top, 60)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: handler.showSuccessToast)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: handler.showErrorToast)
        .allowsHitTesting(false)
    }
}

extension View {
    func tagActionOverlay() -> some View {
        modifier(TagActionOverlayModifier())
    }
    
    func tagActionSheets() -> some View {
        modifier(TagActionSheetModifier())
    }
}
