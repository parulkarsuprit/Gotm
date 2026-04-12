import Foundation
import Vision
import NaturalLanguage
import UIKit
import PDFKit
import FoundationModels

/// Analyzes attachments (images, files) to extract content for title generation
@MainActor
final class AttachmentAnalysisService {
    static let shared = AttachmentAnalysisService()
    
    private init() {}
    
    // MARK: - Main Analysis Entry Point
    
    /// Analyzes all attachments and returns a structured result for title generation
    func analyzeAttachments(_ attachments: [MediaAttachment]) async -> AttachmentAnalysis {
        var allTexts: [String] = []
        var allDocTypes: [String] = []
        var allObjects: [String] = []
        var filenames: [String] = []
        
        for attachment in attachments {
            let result = await analyzeAttachment(attachment)
            if let text = result.extractedText, !text.isEmpty {
                allTexts.append(text)
            }
            if let docType = result.documentType, !docType.isEmpty {
                allDocTypes.append(docType)
            }
            if let object = result.mainObject, !object.isEmpty {
                allObjects.append(object)
            }
            filenames.append(attachment.url.lastPathComponent)
        }
        
        return AttachmentAnalysis(
            extractedText: allTexts.joined(separator: " ").prefix(500).description,
            documentTypes: allDocTypes,
            mainObjects: allObjects,
            filenames: filenames,
            attachmentCount: attachments.count
        )
    }
    
    /// Analyzes a single attachment based on its type
    private func analyzeAttachment(_ attachment: MediaAttachment) async -> SingleAttachmentAnalysis {
        let filename = attachment.url.lastPathComponent
        
        switch attachment.type {
        case .image:
            return await analyzeImage(at: attachment.url, filename: filename)
        case .file:
            return await analyzeFile(at: attachment.url, filename: filename)
        case .audio:
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "Audio Recording",
                mainObject: nil,
                filename: filename
            )
        }
    }
    
    // MARK: - Image Analysis
    
    /// Uses Vision framework to analyze image content comprehensively
    private func analyzeImage(at url: URL, filename: String) async -> SingleAttachmentAnalysis {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "Image",
                mainObject: nil,
                filename: filename
            )
        }
        
        // 1. Image Classification (what's in the image)
        var mainObject: String? = nil
        do {
            mainObject = try await classifyImage(cgImage)
        } catch {
            print("⚠️ [Vision] Classification failed: \(error)")
        }
        
        // 2. Text Recognition (OCR) - prioritize this for documents
        var extractedText: String? = nil
        do {
            let text = try await recognizeText(in: cgImage)
            if text.count > 10 {
                extractedText = text
            }
        } catch {
            print("⚠️ [Vision] Text recognition failed: \(error)")
        }
        
        // Determine if it's a document photo or regular image
        let isDocumentPhoto = extractedText != nil && extractedText!.count > 50
        let documentType = isDocumentPhoto ? "Document Photo" : "Photo"
        
        return SingleAttachmentAnalysis(
            extractedText: extractedText,
            documentType: documentType,
            mainObject: mainObject,
            filename: filename
        )
    }
    
    /// Classifies the main subject of the image
    private func classifyImage(_ cgImage: CGImage) async throws -> String {
        let request = VNClassifyImageRequest()
        request.revision = VNClassifyImageRequestRevision1
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let results = request.results,
              let topResult = results.first(where: { $0.confidence > 0.6 }) else {
            return ""
        }
        
        // Clean up the identifier (e.g., "golden_retriever" -> "golden retriever")
        let clean = topResult.identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        
        return clean
    }
    
    /// Recognizes text in the image using OCR
    private func recognizeText(in cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.01 // Capture small text too
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            return ""
        }
        
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        
        return recognizedStrings.joined(separator: " ")
    }
    
    // MARK: - File Analysis
    
    /// Analyzes file content based on file type with comprehensive extraction
    private func analyzeFile(at url: URL, filename: String) async -> SingleAttachmentAnalysis {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            return await analyzePDF(at: url, filename: filename)
        case "txt", "md", "rtf":
            let text = await extractTextFileContent(at: url)
            return SingleAttachmentAnalysis(
                extractedText: text,
                documentType: ext == "md" ? "Markdown Document" : "Text Document",
                mainObject: nil,
                filename: filename
            )
        case "doc", "docx":
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "Word Document",
                mainObject: nil,
                filename: filename
            )
        case "xls", "xlsx", "numbers":
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "Spreadsheet",
                mainObject: nil,
                filename: filename
            )
        case "ppt", "pptx", "key":
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "Presentation",
                mainObject: nil,
                filename: filename
            )
        case "heic", "jpg", "jpeg", "png", "gif", "webp":
            // Handle image files that were saved as file attachments
            return await analyzeImage(at: url, filename: filename)
        case "json", "xml", "csv":
            let text = await extractTextFileContent(at: url)
            return SingleAttachmentAnalysis(
                extractedText: text,
                documentType: ext.uppercased() + " File",
                mainObject: nil,
                filename: filename
            )
        default:
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: nil,
                mainObject: nil,
                filename: filename
            )
        }
    }
    
    /// Comprehensive PDF analysis with metadata and text extraction
    private func analyzePDF(at url: URL, filename: String) async -> SingleAttachmentAnalysis {
        guard let pdf = PDFDocument(url: url) else {
            return SingleAttachmentAnalysis(
                extractedText: nil,
                documentType: "PDF Document",
                mainObject: nil,
                filename: filename
            )
        }
        
        let pageCount = pdf.pageCount
        
        // Extract title from PDF metadata (documentAttributes is [AnyHashable: Any])
        let pdfTitle = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute.rawValue] as? String
        
        // Extract text from first few pages
        var textContent: [String] = []
        let pagesToScan = min(5, pageCount)
        
        for i in 0..<pagesToScan {
            guard let page = pdf.page(at: i),
                  let text = page.string else { continue }
            textContent.append(text)
        }
        
        let fullText = textContent.joined(separator: " ")
        
        // Extract first paragraph or significant text
        let significantText = extractSignificantText(from: fullText)
        
        return SingleAttachmentAnalysis(
            extractedText: significantText,
            documentType: "\(pageCount)-page PDF",
            mainObject: pdfTitle,
            filename: filename
        )
    }
    
    /// Extracts meaningful content from text files
    private func extractTextFileContent(at url: URL) async -> String? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let cleanContent = content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            
            return String(cleanContent.prefix(400))
        } catch {
            return nil
        }
    }
    
    /// Extracts significant text from PDF content (first sentence or meaningful phrase)
    private func extractSignificantText(from text: String) -> String? {
        let cleanText = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        // Find first sentence that's long enough to be meaningful
        let sentences = cleanText.components(separatedBy: ". ")
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 15 && trimmed.count < 200 {
                return trimmed + "."
            }
        }
        
        // Fallback: return first 150 chars
        if cleanText.count > 20 {
            return String(cleanText.prefix(150)) + "..."
        }
        
        return nil
    }
    
    // MARK: - Intelligent Title Generation
    
    /// Generates a high-quality title using Apple Intelligence when available
    func generateTitleFromAnalysis(_ analysis: AttachmentAnalysis) async -> String {
        // Priority 1: Use AI if available (iOS 26+)
        if #available(iOS 26.0, *) {
            let aiTitle = await generateAITitle(analysis)
            if aiTitle != "Note" && !aiTitle.isEmpty {
                return aiTitle
            }
        }
        
        // Priority 2: Smart heuristic title generation
        let heuristicTitle = generateHeuristicTitle(analysis)
        if heuristicTitle != "Note" {
            return heuristicTitle
        }
        
        // Priority 3: Filename-based fallback
        return generateTitleFromFilename(analysis.filenames.first ?? "Attachment")
    }
    
    /// Uses Apple Language Model for intelligent title generation
    @available(iOS 26.0, *)
    private func generateAITitle(_ analysis: AttachmentAnalysis) async -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return "Note"
        }
        
        // Build rich context for AI
        var contextParts: [String] = []
        
        if let text = analysis.extractedText, !text.isEmpty {
            contextParts.append("Content: \(text.prefix(300))")
        }
        
        if !analysis.documentTypes.isEmpty {
            contextParts.append("Type: \(analysis.documentTypes.joined(separator: ", "))")
        }
        
        if !analysis.mainObjects.isEmpty {
            contextParts.append("Subject: \(analysis.mainObjects.joined(separator: ", "))")
        }
        
        if let filename = analysis.filenames.first {
            contextParts.append("Filename: \(filename)")
        }
        
        let prompt = contextParts.joined(separator: "\n")
        
        let instructions = """
        You are creating a concise title for a document or image. 
        Create a 3-7 word title that captures the main subject or purpose.
        Use Title Case. Be specific and descriptive.
        Focus on what the document IS about, not generic terms.
        Examples:
        - "Q3 Financial Report" not "Document"
        - "Team Meeting Notes" not "Notes"
        - "Apartment Lease Agreement" not "Contract"
        """
        
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            
            // Validate title quality
            if title.count > 3 && title.count < 60 && title != "Note" {
                return applyTitleCase(title)
            }
        } catch {
            print("⚠️ [AttachmentAI] Title generation failed: \(error)")
        }
        
        return "Note"
    }
    
    /// Generates title using smart heuristics (works on all iOS versions)
    private func generateHeuristicTitle(_ analysis: AttachmentAnalysis) -> String {
        // Strategy 1: Extract from document text
        if let text = analysis.extractedText, !text.isEmpty {
            // Look for document type patterns
            let lowerText = text.lowercased()
            
            // Check for common document types
            if lowerText.contains("invoice") || lowerText.contains("bill") {
                if let invoiceNum = extractPattern(from: text, pattern: #"(INV|Invoice|#)\s*[:#]?\s*(\d+)"#) {
                    return "Invoice \(invoiceNum)"
                }
                return "Invoice"
            }
            
            if lowerText.contains("receipt") {
                return "Receipt"
            }
            
            if lowerText.contains("contract") || lowerText.contains("agreement") {
                return "Contract"
            }
            
            if lowerText.contains("resume") || lowerText.contains("cv") {
                return "Resume"
            }
            
            // Extract first meaningful phrase
            let sentences = text.components(separatedBy: ". ")
            for sentence in sentences.prefix(3) {
                let clean = sentence
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\n", with: " ")
                
                if clean.count > 10 && clean.count < 50 {
                    return applyTitleCase(clean)
                }
            }
        }
        
        // Strategy 2: Use document type + subject
        if !analysis.documentTypes.isEmpty {
            let docType = analysis.documentTypes[0]
            
            if !analysis.mainObjects.isEmpty {
                return "\(applyTitleCase(analysis.mainObjects[0])) \(docType)"
            }
            
            return docType
        }
        
        // Strategy 3: Use main object
        if !analysis.mainObjects.isEmpty {
            return applyTitleCase(analysis.mainObjects[0])
        }
        
        return "Note"
    }
    
    /// Extracts patterns like invoice numbers, dates, etc.
    private func extractPattern(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if match.numberOfRanges > 1 {
                let groupRange = match.range(at: match.numberOfRanges - 1)
                if let swiftRange = Range(groupRange, in: text) {
                    return String(text[swiftRange])
                }
            }
        }
        return nil
    }
    
    /// Generates a simple title from filename
    private func generateTitleFromFilename(_ filename: String) -> String {
        let cleanName = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".jpg", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        
        // Limit to 6 words
        let words = cleanName.components(separatedBy: " ").prefix(6)
        return applyTitleCase(words.joined(separator: " "))
    }
    
    /// Applies proper Title Case
    private func applyTitleCase(_ text: String) -> String {
        let smallWords: Set<String> = ["a", "an", "the", "and", "but", "or", "for", "nor", "on", "at", "to", "from", "in", "with"]
        
        let words = text.components(separatedBy: " ")
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index == 0 || index == words.count - 1 || !smallWords.contains(lower) {
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            return lower
        }.joined(separator: " ")
    }
}

// MARK: - Data Models

struct AttachmentAnalysis {
    let extractedText: String?
    let documentTypes: [String]
    let mainObjects: [String]
    let filenames: [String]
    let attachmentCount: Int
}

struct SingleAttachmentAnalysis {
    let extractedText: String?
    let documentType: String?
    let mainObject: String?
    let filename: String
}
