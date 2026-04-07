import Foundation

// MARK: - Context Types

/// The type of application context for dictation cleanup.
/// Dictation style adapts based on where the text will be used.
enum AppType: String, Codable, CaseIterable {
    /// Voice notes and personal memos - preserve natural voice, light cleanup
    case notes = "notes"
    /// Chat/messaging apps - casual, keep contractions, light filler removal
    case chat = "chat"
    /// Email composition - professional, full sentences, aggressive cleanup
    case email = "email"
    /// Documents and formal writing - professional standards, complete sentences
    case document = "document"
    /// Code editors and technical contexts - preserve identifiers, conservative cleanup
    case code = "code"
    /// Search queries - minimal cleanup, keep it concise
    case search = "search"
    
    var displayName: String {
        switch self {
        case .notes: return "Notes"
        case .chat: return "Chat"
        case .email: return "Email"
        case .document: return "Document"
        case .code: return "Code"
        case .search: return "Search"
        }
    }
}

// MARK: - Style Profile

/// User-configurable style preferences for dictation cleanup.
/// These override default behaviors in the rewrite system.
struct StyleProfile: Codable, Equatable {
    /// Use Oxford comma in lists ("A, B, and C" vs "A, B and C")
    var oxfordComma: Bool
    
    /// Preferred dash style for parenthetical asides
    var dashStyle: DashStyle
    
    /// Contraction preference across contexts
    var contractionPreference: ContractionPreference
    
    /// Per-app formality overrides (nil means use default for that app type)
    var formalityOverrides: [String: FormalityLevel]
    
    /// Specific terms with forced casing (e.g., "iPhone", "macOS")
    var capitalisationOverrides: [String: String]
    
    /// Paragraph break frequency
    var paragraphFrequency: ParagraphFrequency
    
    /// List formatting preference
    var listStyle: ListStyle
    
    /// Preferred sentence length
    var sentenceLengthPreference: SentenceLength
    
    /// Ellipsis character preference
    var ellipsisStyle: EllipsisStyle
    
    /// Quotation mark style
    var quotationStyle: QuotationStyle
    
    /// Time format preference
    var timeFormat: TimeFormat
    
    /// Date format preference
    var dateFormat: DateFormat
    
    static let `default` = StyleProfile(
        oxfordComma: true,
        dashStyle: .em,
        contractionPreference: .contextDependent,
        formalityOverrides: [:],
        capitalisationOverrides: [:],
        paragraphFrequency: .moderate,
        listStyle: .inline,
        sentenceLengthPreference: .mixed,
        ellipsisStyle: .ellipsis,
        quotationStyle: .double,
        timeFormat: .twelveHour,
        dateFormat: .us
    )
}

enum DashStyle: String, Codable, CaseIterable {
    case em = "em"           // —
    case en = "en"           // –
    case hyphenSpaced = "hyphen_spaced"  // - 
}

enum ContractionPreference: String, Codable, CaseIterable {
    case always = "always"
    case never = "never"
    case contextDependent = "context_dependent"
}

enum FormalityLevel: String, Codable, CaseIterable {
    case casual = "casual"
    case professionalCasual = "professional_casual"
    case formal = "formal"
}

enum ParagraphFrequency: String, Codable, CaseIterable {
    case dense = "dense"         // Few breaks, longer paragraphs
    case moderate = "moderate"   // Standard breaks
    case sparse = "sparse"       // More breaks, shorter paragraphs
}

enum ListStyle: String, Codable, CaseIterable {
    case inline = "inline"           // "first, second, third"
    case bulleted = "bulleted"       // Bullet points
    case numbered = "numbered"       // 1. 2. 3.
}

enum SentenceLength: String, Codable, CaseIterable {
    case short = "short"
    case mixed = "mixed"
    case long = "long"
}

enum EllipsisStyle: String, Codable, CaseIterable {
    case ellipsis = "…"     // Single character
    case dots = "..."       // Three periods
}

enum QuotationStyle: String, Codable, CaseIterable {
    case double = "double"  // "text"
    case single = "single"  // 'text'
}

enum TimeFormat: String, Codable, CaseIterable {
    case twelveHour = "12h"  // 3:30 PM
    case twentyFourHour = "24h"  // 15:30
}

enum DateFormat: String, Codable, CaseIterable {
    case us = "us"           // March 15, 2026
    case uk = "uk"           // 15 March 2026
    case iso = "iso"         // 2026-03-15
}

// MARK: - Rewrite Context

/// Complete context for a dictation rewrite operation.
/// Passed to the transcription service to guide cleanup behavior.
struct RewriteContext: Codable, Equatable {
    /// The target app type (determines base formality and style)
    let appType: AppType
    
    /// Optional description of recipient or context (e.g., "Reply to engineering team")
    let recipientContext: String?
    
    /// Text that precedes this segment (for context-aware decisions)
    let precedingText: String?
    
    /// User's style profile preferences
    let styleProfile: StyleProfile?
    
    /// Terms from personal dictionary to prioritize
    let personalDictionaryTerms: [String]
    
    /// User's locale for region-specific formatting
    let locale: String
    
    /// Detected language code
    let detectedLanguage: String
    
    init(
        appType: AppType = .notes,
        recipientContext: String? = nil,
        precedingText: String? = nil,
        styleProfile: StyleProfile? = nil,
        personalDictionaryTerms: [String] = [],
        locale: String = "en-US",
        detectedLanguage: String = "en"
    ) {
        self.appType = appType
        self.recipientContext = recipientContext
        self.precedingText = precedingText
        self.styleProfile = styleProfile
        self.personalDictionaryTerms = personalDictionaryTerms
        self.locale = locale
        self.detectedLanguage = detectedLanguage
    }
    
    /// Default context for voice notes
    static let `default` = RewriteContext(
        appType: .notes,
        locale: Locale.current.identifier,
        detectedLanguage: "en"
    )
}

// MARK: - Endpoint Metadata

/// Metadata about the speech segment being processed.
struct EndpointMetadata: Codable, Equatable {
    /// Type of pause that triggered this segment
    let pauseType: PauseType
    
    /// Duration of the segment in milliseconds
    let segmentDurationMs: Int
    
    /// Whether this is a continuation of previous speech
    let isContinuation: Bool
    
    /// Confidence score from the ASR engine (0.0-1.0)
    let confidence: Double?
}

enum PauseType: String, Codable {
    case sentenceEnd = "sentence_end"
    case paragraphPause = "paragraph_pause"
    case manualStop = "manual_stop"
    case timeout = "timeout"
}

// MARK: - User Message Format

/// The complete payload sent to the AI formatter.
struct RewriteRequest: Codable {
    /// The raw transcript from the ASR engine
    let rawTranscript: String
    
    /// Context metadata for style adaptation
    let context: RewriteContext
    
    /// Endpoint detection metadata
    let endpointMetadata: EndpointMetadata?
}
