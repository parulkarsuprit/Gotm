import Foundation
import SwiftUI

// MARK: - Rewrite Settings

/// Persistent user settings for the dictation rewrite system.
/// Stores style profile and app type preferences.
@MainActor
final class RewriteSettings: ObservableObject {
    static let shared = RewriteSettings()
    
    @Published var styleProfile: StyleProfile {
        didSet { save() }
    }
    
    @Published var defaultAppType: AppType {
        didSet { save() }
    }
    
    @Published var enableAIFormatting: Bool {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    private let styleProfileKey = "rewrite_style_profile"
    private let defaultAppTypeKey = "rewrite_default_app_type"
    private let enableAIFormattingKey = "rewrite_enable_ai_formatting"
    
    private init() {
        // Load style profile
        if let data = defaults.data(forKey: styleProfileKey),
           let profile = try? JSONDecoder().decode(StyleProfile.self, from: data) {
            self.styleProfile = profile
        } else {
            self.styleProfile = .default
        }
        
        // Load default app type
        if let rawValue = defaults.string(forKey: defaultAppTypeKey),
           let type = AppType(rawValue: rawValue) {
            self.defaultAppType = type
        } else {
            self.defaultAppType = .notes
        }
        
        // Load AI formatting preference
        self.enableAIFormatting = defaults.object(forKey: enableAIFormattingKey) as? Bool ?? true
    }
    
    /// Get a rewrite context for the current settings
    func rewriteContext(
        appType: AppType? = nil,
        recipientContext: String? = nil,
        precedingText: String? = nil
    ) -> RewriteContext {
        let dictionary = PersonalDictionary.shared
        let relevantTerms = dictionary.allTerms
        
        return RewriteContext(
            appType: appType ?? defaultAppType,
            recipientContext: recipientContext,
            precedingText: precedingText,
            styleProfile: styleProfile,
            personalDictionaryTerms: relevantTerms,
            locale: Locale.current.identifier,
            detectedLanguage: "en"
        )
    }
    
    /// Update a specific style profile property
    func updateStyleProfile(_ update: (inout StyleProfile) -> Void) {
        var profile = styleProfile
        update(&profile)
        styleProfile = profile
    }
    
    /// Reset to defaults
    func resetToDefaults() {
        styleProfile = .default
        defaultAppType = .notes
        enableAIFormatting = true
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let data = try? JSONEncoder().encode(styleProfile) {
            defaults.set(data, forKey: styleProfileKey)
        }
        defaults.set(defaultAppType.rawValue, forKey: defaultAppTypeKey)
        defaults.set(enableAIFormatting, forKey: enableAIFormattingKey)
    }
}

// MARK: - Preview Helpers

extension RewriteSettings {
    static var preview: RewriteSettings {
        let settings = RewriteSettings()
        settings.styleProfile = .default
        settings.defaultAppType = .notes
        settings.enableAIFormatting = true
        return settings
    }
}
