import Combine
import MessageUI
import SwiftUI
import Observation

/// Service for composing emails from voice notes
@MainActor
@Observable
final class EmailService {
    static let shared = EmailService()
    
    var isShowingMailCompose = false
    var mailData: MailData?
    
    private init() {}
    
    /// Check if device can send mail
    var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
    
    /// Show email compose sheet pre-filled with voice note content
    func composeEmail(
        subject: String? = nil,
        body: String,
        recipients: [String] = [],
        isHTML: Bool = false
    ) {
        guard canSendMail else {
            // Fallback: copy to clipboard and show alert
            UIPasteboard.general.string = body
            print("⚠️ [Email] Mail not configured. Content copied to clipboard.")
            return
        }
        
        mailData = MailData(
            subject: subject ?? "Note from Gotm",
            body: body,
            recipients: recipients,
            isHTML: isHTML
        )
        isShowingMailCompose = true
    }
    
    /// Create email from a recording entry
    func composeEmailFromEntry(_ entry: RecordingEntry) {
        let subject = entry.name != "Loading…" ? entry.name : "Voice Note"
        
        var body = ""
        
        // Add transcript if available
        if let transcript = entry.transcript, !transcript.isEmpty {
            body += transcript
        }
        
        // Add tags
        if !entry.tags.isEmpty {
            let tagLabels = entry.tags.map { $0.type.label }.joined(separator: ", ")
            body += "\n\n—\nTags: \(tagLabels)"
        }
        
        // Add metadata
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        body += "\nRecorded: \(formatter.string(from: entry.date))"
        
        composeEmail(subject: subject, body: body)
    }
    
    /// Share via system share sheet (for when Mail isn't configured)
    func shareViaSystemSheet(_ items: [Any], from viewController: UIViewController? = nil) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Exclude some activities for cleaner UI
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .print,
            .addToReadingList
        ]
        
        // Present from root view controller
        let rootVC = viewController ?? UIApplication.shared.firstKeyWindow?.rootViewController
        if let rootVC = rootVC {
            if let presented = rootVC.presentedViewController {
                presented.present(activityVC, animated: true)
            } else {
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: - UIApplication Helper

extension UIApplication {
    /// Returns the first key window from the active window scene (modern replacement for deprecated keyWindow)
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            .flatMap { $0.windows.first { $0.isKeyWindow } }
    }
}

// MARK: - Mail Data

struct MailData {
    let subject: String
    let body: String
    let recipients: [String]
    let isHTML: Bool
}

// MARK: - Mail Compose View (SwiftUI Wrapper)

struct MailComposeView: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    let mailData: MailData?
    var onResult: ((MFMailComposeResult, Error?) -> Void)?
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        
        if let data = mailData {
            vc.setSubject(data.subject)
            vc.setMessageBody(data.body, isHTML: data.isHTML)
            vc.setToRecipients(data.recipients)
        }
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            parent.isShowing = false
            parent.onResult?(result, error)
            
            switch result {
            case .sent:
                print("✅ [Email] Message sent")
            case .saved:
                print("✅ [Email] Message saved as draft")
            case .cancelled:
                print("ℹ️ [Email] User cancelled")
            case .failed:
                print("❌ [Email] Failed: \(error?.localizedDescription ?? "Unknown error")")
            @unknown default:
                break
            }
        }
    }
}
