import Combine
import SwiftUI
import Observation

/// Service for sharing voice notes to Apple Notes and other apps
@MainActor
@Observable
final class NotesService {
    static let shared = NotesService()
    
    var isShowingShareSheet = false
    var shareItems: [Any] = []
    var shareSubject: String?
    
    private init() {}
    
    /// Share a recording entry to Notes or other apps
    func shareEntry(_ entry: RecordingEntry, format: ShareFormat = .formatted) {
        let content = formatContent(entry, format: format)
        
        shareItems = [content]
        shareSubject = entry.name != "Loading…" ? entry.name : "Voice Note"
        
        // Small delay to ensure state update propagates
        DispatchQueue.main.async {
            self.isShowingShareSheet = true
        }
    }
    
    /// Share just the transcript text
    func shareTranscript(_ transcript: String, title: String? = nil) {
        shareItems = [transcript]
        shareSubject = title
        isShowingShareSheet = true
    }
    
    /// Export entry as formatted text
    func exportAsText(_ entry: RecordingEntry) -> String {
        formatContent(entry, format: .formatted)
    }
    
    /// Copy entry content to clipboard
    func copyToClipboard(_ entry: RecordingEntry, format: ShareFormat = .formatted) {
        let content = formatContent(entry, format: format)
        UIPasteboard.general.string = content
    }
    
    // MARK: - Formatting Options
    
    enum ShareFormat {
        case formatted   // Title + transcript + tags + metadata
        case transcriptOnly  // Just the transcript
        case markdown    // Markdown formatted
    }
    
    private func formatContent(_ entry: RecordingEntry, format: ShareFormat) -> String {
        switch format {
        case .formatted:
            return formatAsText(entry)
        case .transcriptOnly:
            return entry.transcript ?? entry.name
        case .markdown:
            return formatAsMarkdown(entry)
        }
    }
    
    private func formatAsText(_ entry: RecordingEntry) -> String {
        var text = ""
        
        // Title
        if entry.name != "Loading…" {
            text += entry.name + "\n"
            text += String(repeating: "=", count: entry.name.count) + "\n\n"
        }
        
        // Transcript
        if let transcript = entry.transcript, !transcript.isEmpty {
            text += transcript
            text += "\n\n"
        }
        
        // Tags
        if !entry.tags.isEmpty {
            let tagLabels = entry.tags.map { "• " + $0.type.label }.joined(separator: "\n")
            text += "Tags:\n" + tagLabels + "\n\n"
        }
        
        // Metadata
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        text += "—\n"
        text += "Recorded: \(formatter.string(from: entry.date))"
        
        if entry.duration > 0 {
            text += "\nDuration: \(formatDuration(entry.duration))"
        }
        
        text += "\nFrom Gotm"
        
        return text
    }
    
    private func formatAsMarkdown(_ entry: RecordingEntry) -> String {
        var text = ""
        
        // Title
        if entry.name != "Loading…" {
            text += "# " + entry.name + "\n\n"
        }
        
        // Tags as badges
        if !entry.tags.isEmpty {
            let tags = entry.tags.map { "**" + $0.type.label + "**" }.joined(separator: " ")
            text += tags + "\n\n"
        }
        
        // Transcript
        if let transcript = entry.transcript, !transcript.isEmpty {
            text += transcript
            text += "\n\n"
        }
        
        // Metadata
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        text += "---\n"
        text += "*Recorded: \(formatter.string(from: entry.date))*"
        
        if entry.duration > 0 {
            text += " *• Duration: \(formatDuration(entry.duration))*"
        }
        
        text += "  \n*From [Gotm](gotm.app)*"
        
        return text
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Share Sheet View (SwiftUI Wrapper)

struct ShareSheetView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]
    let subject: String?
    var excludedTypes: [UIActivity.ActivityType]?
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, uiViewController.presentedViewController == nil else { return }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Set subject for email
        if let subject = subject {
            activityVC.setValue(subject, forKey: "subject")
        }
        
        // Exclude some activities for cleaner UI
        var excluded: [UIActivity.ActivityType] = [
            .assignToContact,
            .addToReadingList
        ]
        
        // Add custom exclusions if provided
        if let customExcluded = excludedTypes {
            excluded.append(contentsOf: customExcluded)
        }
        
        activityVC.excludedActivityTypes = excluded
        
        // Completion handler
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        
        // Present on main thread
        DispatchQueue.main.async {
            uiViewController.present(activityVC, animated: true)
        }
    }
}
