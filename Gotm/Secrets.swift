import Foundation

/// Secure storage for API keys and sensitive configuration
enum Secrets {
    
    /// Deepgram API Key for transcription services
    /// First checks Keychain, then falls back to build settings (migration path)
    static var deepgramAPIKey: String {
        // Priority 1: Keychain (most secure, persisted)
        if let keychainKey = KeychainService.load(.deepgramAPIKey),
           !keychainKey.isEmpty {
            return keychainKey
        }
        
        // Priority 2: Build settings (for CI/production or first launch)
        if let buildKey = Bundle.main.object(forInfoDictionaryKey: "DEEPGRAM_API_KEY") as? String,
           !buildKey.isEmpty,
           !buildKey.contains("your_deepgram") {
            // Migrate to keychain for future use
            KeychainService.save(buildKey, for: .deepgramAPIKey)
            return buildKey
        }
        
        // Priority 3: Environment variable (local development)
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"],
           !envKey.isEmpty {
            // Migrate to keychain for future use
            KeychainService.save(envKey, for: .deepgramAPIKey)
            return envKey
        }
        
        // Not configured
        #if DEBUG
        print("⚠️ [Secrets] DEEPGRAM_API_KEY not set. Transcription will fail.")
        print("⚠️ [Secrets] Add your key to Config/Secrets.xcconfig")
        #endif
        
        return ""
    }
    
    /// Check if required secrets are configured
    static var isConfigured: Bool {
        !deepgramAPIKey.isEmpty
    }
    
    /// Manually set API key (for settings UI)
    static func setAPIKey(_ key: String) -> Bool {
        return KeychainService.save(key, for: .deepgramAPIKey)
    }
    
    /// Clear stored API key
    static func clearAPIKey() {
        KeychainService.delete(.deepgramAPIKey)
    }
}
