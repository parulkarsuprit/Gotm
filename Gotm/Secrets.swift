import Foundation

/// Secure storage for API keys and sensitive configuration
/// Keys are injected at build time from Secrets.xcconfig (not in git)
enum Secrets {
    
    /// Deepgram API Key for transcription services
    /// Set in Secrets.xcconfig as DEEPGRAM_API_KEY
    static let deepgramAPIKey: String = {
        // Try to get from build settings first (production/ci)
        if let key = Bundle.main.object(forInfoDictionaryKey: "DEEPGRAM_API_KEY") as? String,
           !key.isEmpty,
           !key.contains("your_deepgram") {
            return key
        }
        
        // Fallback to environment variable (local development)
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        
        // Development placeholder - app will show error for transcription
        #if DEBUG
        print("⚠️ [Secrets] DEEPGRAM_API_KEY not set. Transcription will fail.")
        print("⚠️ [Secrets] Copy Config/Template.xcconfig to Config/Secrets.xcconfig and add your key")
        #endif
        
        return ""
    }()
    
    /// Check if required secrets are configured
    static var isConfigured: Bool {
        !deepgramAPIKey.isEmpty
    }
}
