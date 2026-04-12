import Foundation
import Observation

/// Supported languages for transcription
enum SupportedLanguage: String, Codable, CaseIterable, Identifiable {
    case auto = "auto"           // Auto-detect
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "Auto-Detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        }
    }
    
    var localeIdentifier: String {
        switch self {
        case .auto: return "auto"
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .italian: return "it-IT"
        case .portuguese: return "pt-BR"
        case .dutch: return "nl-NL"
        case .russian: return "ru-RU"
        case .chinese: return "zh-CN"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .arabic: return "ar-SA"
        case .hindi: return "hi-IN"
        }
    }
    
    /// WhisperKit language code
    var whisperCode: String? {
        switch self {
        case .auto: return nil  // Auto-detect
        case .english: return "en"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .dutch: return "nl"
        case .russian: return "ru"
        case .chinese: return "zh"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .arabic: return "ar"
        case .hindi: return "hi"
        }
    }
    
    /// Deepgram language code
    var deepgramCode: String? {
        switch self {
        case .auto: return nil  // Use detect_language
        default: return rawValue
        }
    }
    
    /// Whether this language uses WhisperKit multilingual model
    var usesMultilingualModel: Bool {
        // Only English can use the optimized English model
        // All others need the multilingual model
        self != .english
    }
}

/// Service for managing language preferences and detection
@MainActor
@Observable
final class LanguageService {
    static let shared = LanguageService()
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "selectedTranscriptionLanguage"
    
    /// Currently selected language for transcription
    var selectedLanguage: SupportedLanguage {
        didSet {
            saveLanguagePreference()
        }
    }
    
    /// Whether auto-detection is enabled
    var isAutoDetectEnabled: Bool {
        selectedLanguage == .auto
    }
    
    private init() {
        // Load saved preference or default to auto
        if let savedCode = userDefaults.string(forKey: languageKey),
           let language = SupportedLanguage(rawValue: savedCode) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = .auto
        }
    }
    
    private func saveLanguagePreference() {
        userDefaults.set(selectedLanguage.rawValue, forKey: languageKey)
    }
    
    /// Get the best locale for SFSpeechRecognizer
    func currentLocale() -> Locale {
        if isAutoDetectEnabled {
            // Return device's current locale for auto
            return Locale.current
        }
        return Locale(identifier: selectedLanguage.localeIdentifier)
    }
    
    /// Get the language code for WhisperKit
    func whisperLanguageCode() -> String? {
        if isAutoDetectEnabled {
            return nil  // Auto-detect
        }
        return selectedLanguage.whisperCode
    }
    
    /// Get Deepgram language parameter
    func deepgramLanguageParam() -> String {
        if isAutoDetectEnabled {
            return "detect_language=true"
        }
        if let code = selectedLanguage.deepgramCode {
            return "language=\(code)"
        }
        return "detect_language=true"
    }
    
    /// Detect language from text sample (simple heuristic)
    func detectLanguage(from text: String) -> SupportedLanguage {
        // Simple character-based detection
        let sample = text.prefix(100)
        
        // Check for specific scripts
        if sample.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return .chinese
        }
        if sample.range(of: "\\p{Hiragana}|\\p{Katakana}", options: .regularExpression) != nil {
            return .japanese
        }
        if sample.range(of: "\\p{Hangul}", options: .regularExpression) != nil {
            return .korean
        }
        if sample.range(of: "\\p{Arabic}", options: .regularExpression) != nil {
            return .arabic
        }
        if sample.range(of: "\\p{Devanagari}", options: .regularExpression) != nil {
            return .hindi
        }
        if sample.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil {
            return .russian
        }
        
        // Default to English for Latin scripts
        return .english
    }
    
    /// Get contextual strings for speech recognition based on language
    func contextualStrings() -> [String] {
        // Common app terms in different languages
        switch selectedLanguage {
        case .spanish:
            return ["reunión", "recordatorio", "llamada", "comprar", "tarea"]
        case .french:
            return ["réunion", "rappel", "appel", "acheter", "tâche"]
        case .german:
            return ["besprechung", "erinnerung", "anruf", "kaufen", "aufgabe"]
        case .chinese:
            return ["会议", "提醒", "电话", "购买", "任务"]
        case .japanese:
            return ["会議", "リマインダー", "電話", "購入", "タスク"]
        default:
            return ["meeting", "reminder", "call", "email", "todo", "shopping", "buy", "schedule"]
        }
    }
}
