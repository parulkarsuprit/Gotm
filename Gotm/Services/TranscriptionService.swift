import Foundation
import FoundationModels
import Speech
import WhisperKit

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private var whisperKit: WhisperKit?
    private var warmUpTask: Task<Void, Never>?

    // SFSpeechRecognizer — streams audio during recording, result ready when recording stops
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveTranscript = ""
    private var isStreaming = false

    private init() {
        Task { await warmUp() }
    }

    // MARK: - Warmup

    func warmUp() async {
        // Request speech recognition permission early so first recording isn't delayed
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }

        if let existing = warmUpTask {
            await existing.value
            return
        }
        let task = Task {
            do {
                self.whisperKit = try await WhisperKit(model: "small.en")
                print("✅ [WhisperKit] Model loaded and ready")
            } catch {
                print("❌ [WhisperKit] Warm-up failed: \(error)")
            }
        }
        warmUpTask = task
        await task.value
    }

    // MARK: - SFSpeechRecognizer streaming

    func startStreaming() {
        // Use US English for best recognition accuracy
        let locale = Locale(identifier: "en-US")
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("⚠️ [Speech] Recognizer unavailable for locale \(locale.identifier)")
            return
        }
        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // CRITICAL: Use on-device recognition for better accuracy and privacy
        // Server-based recognition often has issues with short audio or quick speech
        if #available(iOS 15, *) {
            request.requiresOnDeviceRecognition = true
        }
        
        // Enable all available recognition features
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        if #available(iOS 16, *) {
            request.contextualStrings = ["meeting", "reminder", "call", "email", "todo", "shopping", "buy", "schedule"]
        }
        
        recognitionRequest = request
        liveTranscript = ""
        isStreaming = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.liveTranscript = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.isStreaming = false
            }
        }

        // Feed audio buffers directly into the recognizer during recording
        RecordingService.shared.onAudioPCMBuffer = { [weak self] buffer in
            self?.recognitionRequest?.append(buffer)
        }

        print("🎙️ [Speech] Live recognition started")
    }

    func finishStreaming() async -> String {
        RecordingService.shared.onAudioPCMBuffer = nil

        recognitionRequest?.endAudio()

        // Give the recognizer up to 300ms to finalise the last words
        var waited = 0
        while isStreaming && waited < 300 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 50
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        isStreaming = false

        let result = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""
        print("✅ [Speech] Final: \(result.prefix(80))")
        return result
    }

    // MARK: - Foundation Models Smart Formatting

    /// Post-processes a transcript with Apple Intelligence using the full production prompt.
    /// Returns the original string unchanged if formatting fails or the model is unavailable.
    @MainActor
    func formatWithAI(
        _ transcript: String,
        context: RewriteContext? = nil,
        endpointMetadata: EndpointMetadata? = nil
    ) async -> String {
        let context = context ?? RewriteContext.default
        // Skip very short notes — nothing meaningful to clean
        guard transcript.split(separator: " ").count > 8 else { return transcript }

        guard #available(iOS 26.0, *) else { return transcript }
        
        // Access language model on MainActor
        let model = getLanguageModel()
        guard case .available = model.availability else { return transcript }

        do {
            let systemPrompt = buildSystemPrompt()
            let session = LanguageModelSession(instructions: systemPrompt)
            
            let userMessage = buildUserMessage(
                transcript: transcript,
                context: context,
                endpointMetadata: endpointMetadata
            )
            
            let response = try await session.respond(to: userMessage)
            let formatted = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !formatted.isEmpty,
                  !Self.isGarbageResponse(formatted, comparedTo: transcript) else {
                print("⚠️ [Transcription] AI formatter returned garbage — keeping original")
                return transcript
            }
            return formatted
        } catch {
            print("⚠️ [Transcription] AI formatting failed: \(error)")
            return transcript
        }
    }
    
    /// Helper to access MainActor-isolated SystemLanguageModel
    @MainActor
    private func getLanguageModel() -> SystemLanguageModel {
        SystemLanguageModel.default
    }

    /// Builds the comprehensive production system prompt.
    /// Loads from bundled DictationPrompt.md file if available, otherwise uses inline fallback.
    private func buildSystemPrompt() -> String {
        // Try to load from bundled file first
        if let url = Bundle.main.url(forResource: "DictationPrompt", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        
        // Fallback: load from Resources directory in source
        #if DEBUG
        print("⚠️ [Transcription] DictationPrompt.md not found in bundle, using inline fallback")
        #endif
        
        return loadFallbackPrompt()
    }
    
    /// Inline fallback prompt (condensed version)
    private func loadFallbackPrompt() -> String {
        """
        You are a dictation cleanup engine. Transform raw speech-to-text into clean written text.
        
        CORE RULES:
        1. PRESERVE MEANING EXACTLY - never add/remove content
        2. SOUND LIKE THE USER - match their style
        3. CLEAN SPEECH ARTIFACTS - remove fillers, fix false starts
        
        FILLER REMOVAL (when not meaningful):
        - Remove: um, uh, er, ah, basically, literally (as fillers)
        - Keep: "like" for comparison, "actually" for contrast, "I mean" for clarification
        
        SELF-CORRECTIONS:
        - "X no Y" → Y
        - "X I mean Y" → Y
        - "the the" → "the"
        
        FORMATTING:
        - Add proper punctuation
        - Capitalize sentences and proper nouns
        - "three pm" → "3 PM"
        - "twenty dollars" → "$20"
        
        CONTEXT (app_type):
        - email: Professional, "gonna" → "going to"
        - chat: Casual, keep "gonna"
        - notes: Natural voice
        
        NEVER:
        - Add content not said
        - Summarize
        - Use markdown
        - Explain changes
        
        Return ONLY the cleaned text.
        """
    }

    /// Builds the user message with context and metadata.
    private func buildUserMessage(
        transcript: String,
        context: RewriteContext,
        endpointMetadata: EndpointMetadata?
    ) -> String {
        // Build context JSON
        var contextDict: [String: Any] = [
            "app_type": context.appType.rawValue,
            "locale": context.locale,
            "detected_language": context.detectedLanguage
        ]
        
        if let recipient = context.recipientContext {
            contextDict["recipient_context"] = recipient
        }
        
        if let preceding = context.precedingText {
            contextDict["preceding_text"] = preceding
        }
        
        if let profile = context.styleProfile {
            var profileDict: [String: Any] = [
                "oxford_comma": profile.oxfordComma,
                "dash_style": profile.dashStyle.rawValue,
                "contraction_preference": profile.contractionPreference.rawValue,
                "paragraph_frequency": profile.paragraphFrequency.rawValue,
                "list_style": profile.listStyle.rawValue,
                "sentence_length_preference": profile.sentenceLengthPreference.rawValue,
                "ellipsis_style": profile.ellipsisStyle.rawValue,
                "quotation_style": profile.quotationStyle.rawValue,
                "time_format": profile.timeFormat.rawValue,
                "date_format": profile.dateFormat.rawValue
            ]
            
            if !profile.formalityOverrides.isEmpty {
                var overrides: [String: String] = [:]
                for (key, value) in profile.formalityOverrides {
                    overrides[key] = value.rawValue
                }
                profileDict["formality_overrides"] = overrides
            }
            
            if !profile.capitalisationOverrides.isEmpty {
                profileDict["capitalisation_overrides"] = profile.capitalisationOverrides
            }
            
            contextDict["style_profile"] = profileDict
        }
        
        if !context.personalDictionaryTerms.isEmpty {
            contextDict["personal_dictionary"] = context.personalDictionaryTerms
        }
        
        // Build endpoint metadata
        var endpointDict: [String: Any]?
        if let metadata = endpointMetadata {
            var dict: [String: Any] = [
                "pause_type": metadata.pauseType.rawValue,
                "segment_duration_ms": metadata.segmentDurationMs,
                "is_continuation": metadata.isContinuation
            ]
            if let confidence = metadata.confidence {
                dict["confidence"] = confidence
            }
            endpointDict = dict
        }
        
        // Assemble the user message as JSON for clarity
        var messageDict: [String: Any] = [
            "raw_transcript": transcript,
            "context": contextDict
        ]
        
        if let endpoint = endpointDict {
            messageDict["endpoint_metadata"] = endpoint
        }
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback: simple format
        return """
        Raw transcript: \(transcript)
        
        Context: \(context.appType.rawValue)
        """
    }

    /// Returns true if the model response looks like a refusal, leaked instructions, or is completely off-topic.
    private static func isGarbageResponse(_ response: String, comparedTo original: String) -> Bool {
        let lower = response.lowercased()

        // Refusal or conversational openers — AI talking back instead of formatting
        let refusalPrefixes = [
            "i'm sorry", "i am sorry", "i cannot", "i can't", "as a chatbot",
            "as a language model", "as an ai", "certainly!", "sure!", "of course!",
            "i'd be happy", "i would be happy", "i apologize",
            "i'm here to help", "im here to help", "i am here to help",
            "how can i help", "how may i help", "what can i do",
            "what would you like", "how can i assist", "hello!", "hi!",
            "greetings!", "hey there", "i'm an ai", "i am an ai"
        ]
        if refusalPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        
        // Conversational phrases anywhere in response
        let conversationalPhrases = [
            "i'm here to help", "im here to help", "how can i help you",
            "what can i do for you", "how may i assist you",
            "i'm just an ai", "i'm an ai assistant", "as your ai assistant"
        ]
        if conversationalPhrases.contains(where: { lower.contains($0) }) { return true }

        // Leaked instruction phrases — verbatim strings from our own system prompt
        let leakedPhrases = [
            "filler word removal",
            "self-correction resolution",
            "preserve meaning exactly",
            "never add content",
            "dictation cleanup engine",
            "return only the cleaned text",
            "paragraph breaks",
            "context-conditioned tone",
            "personal dictionary",
            "style profile",
            "as an ai language model"
        ]
        if leakedPhrases.contains(where: { lower.contains($0) }) { return true }

        // Response is more than 4x the length of the input — model hallucinated
        if response.count > original.count * 4 { return true }
        
        // Response is much shorter than input (significant content was lost)
        if response.count < Int(Double(original.count) * 0.3) && original.count > 50 { return true }

        return false
    }

    // MARK: - Deepgram background refinement

    /// Calls Deepgram batch and returns the transcript, or nil on failure.
    /// Use this after showing an optimistic SFSpeechRecognizer result to silently improve accuracy.
    func refineWithDeepgram(fileURL: URL) async -> String? {
        do {
            let result = try await transcribeViaDeepgram(fileURL: fileURL)
            return result.isEmpty ? nil : result
        } catch {
            print("⚠️ [Deepgram] Background refinement failed: \(error)")
            return nil
        }
    }

    // MARK: - Deepgram batch (fallback)

    func transcribeViaDeepgram(fileURL: URL) async throws -> String {
        guard !Secrets.deepgramAPIKey.isEmpty else {
            print("❌ [Deepgram] API key not configured")
            throw TranscriptionError.deepgramFailed
        }
        
        let url = URL(string: "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&detect_language=true")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(Secrets.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("❌ [Deepgram Batch] HTTP \(code)")
            throw TranscriptionError.deepgramFailed
        }

        let decoded = try JSONDecoder().decode(DeepgramResponse.self, from: data)
        guard let transcript = decoded.results.channels.first?.alternatives.first?.transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Main entry point

    func transcribe(fileURL: URL) async throws -> String {
        print("🎯 [Transcription] Starting: \(fileURL.lastPathComponent)")
        
        // Get file size to detect long recordings
        let fileSize: UInt64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attributes[.size] as? UInt64 ?? 0
        } catch {
            fileSize = 0
        }
        
        // For files larger than ~2MB (roughly 2+ minutes), skip SFSpeechRecognizer 
        // and go directly to Deepgram which handles long audio better
        let isLongRecording = fileSize > 2_000_000
        
        if !isLongRecording {
            // 1. SFSpeechRecognizer — instant result accumulated during recording
            // Only for short recordings where streaming works well
            let liveTranscript = await finishStreaming()
            if liveTranscript.count > 20 {
                print("⚡ [Speech] Instant result (\(liveTranscript.count) chars)")
                return liveTranscript
            }
        } else {
            // For long recordings, just stop the streaming without waiting for result
            _ = await finishStreaming()
            print("📝 [Transcription] Long recording detected (\(fileSize / 1024)KB), using Deepgram")
        }

        // 2. Deepgram nova-2 — best for long recordings and when SFSpeechRecognizer fails
        do {
            // Add timeout for long recordings
            let transcript: String
            if isLongRecording {
                // Longer timeout for big files
                transcript = try await withTimeout(seconds: 60) {
                    try await self.transcribeViaDeepgram(fileURL: fileURL)
                }
            } else {
                transcript = try await transcribeViaDeepgram(fileURL: fileURL)
            }
            print("✅ [Deepgram] Done: \(transcript.prefix(80))")
            return transcript
        } catch {
            print("⚠️ [Deepgram] Failed (\(error)) — falling back to WhisperKit")
        }

        // 3. WhisperKit — last resort offline fallback
        if whisperKit == nil { await warmUp() }
        guard let kit = whisperKit else {
            throw TranscriptionError.modelLoadFailed
        }

        let options = DecodingOptions(task: .transcribe, language: "en", withoutTimestamps: true)
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("✅ [WhisperKit] Done: \(text.prefix(80))")
        return text
    }
    
    /// Helper to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual work
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TranscriptionError.timeout
            }
            
            // Return first result and cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Deepgram batch response models

private struct DeepgramResponse: Decodable {
    let results: DeepgramResults
}
private struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}
private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}
private struct DeepgramAlternative: Decodable {
    let transcript: String
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelLoadFailed
    case inferenceFailed
    case deepgramFailed
    case emptyTranscript
    case apiKeyMissing
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Could not load transcription model"
        case .inferenceFailed:
            return "Transcription failed - please try again"
        case .deepgramFailed:
            return "Network transcription failed - using offline backup"
        case .emptyTranscript:
            return "No speech detected"
        case .apiKeyMissing:
            return "Transcription service not configured"
        case .timeout:
            return "Transcription timed out - please try again"
        }
    }
}
