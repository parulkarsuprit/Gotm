import SwiftUI
import QuickLook

/// Preview files using native QuickLook
struct FilePreviewView: View {
    let attachments: [MediaAttachment]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        QuickLookPreviewController(
            attachments: attachments,
            initialIndex: initialIndex,
            onDismiss: { dismiss() }
        )
        .ignoresSafeArea()
    }
}

struct QuickLookPreviewController: UIViewControllerRepresentable {
    let attachments: [MediaAttachment]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        print("📎 [QuickLook] Creating preview for \(attachments.count) items")
        
        let previewVC = QLPreviewController()
        previewVC.dataSource = context.coordinator
        previewVC.delegate = context.coordinator
        previewVC.currentPreviewItemIndex = initialIndex
        
        let navController = UINavigationController(rootViewController: previewVC)
        
        // Add done button
        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.doneTapped)
        )
        previewVC.navigationItem.rightBarButtonItem = doneButton
        
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookPreviewController
        
        init(_ parent: QuickLookPreviewController) {
            self.parent = parent
            super.init()
            
            // Log all attachments
            for (i, att) in parent.attachments.enumerated() {
                print("📎 [QuickLook] Item \(i): \(att.url.lastPathComponent)")
                print("📎 [QuickLook]   Path: \(att.url.path)")
                print("📎 [QuickLook]   Exists: \(FileManager.default.fileExists(atPath: att.url.path))")
                print("📎 [QuickLook]   Type: \(att.type)")
            }
        }
        
        @objc func doneTapped() {
            parent.onDismiss()
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return parent.attachments.count
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            let url = parent.attachments[index].url
            print("📎 [QuickLook] Providing item at index \(index): \(url.lastPathComponent)")
            return url as QLPreviewItem
        }
        
        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            parent.onDismiss()
        }
    }
}

// MARK: - Simple Views for other file types

struct AsyncImagePreview: View {
    let url: URL
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task {
                let loaded = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path)
                }.value
                await MainActor.run {
                    self.image = loaded
                    self.isLoading = false
                }
            }
        }
    }
}

struct GenericFilePreview: View {
    let url: URL
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text(url.lastPathComponent)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.white)
            
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "play.rectangle"
        default: return "doc.fill"
        }
    }
}
