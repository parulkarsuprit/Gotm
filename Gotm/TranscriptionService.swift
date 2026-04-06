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
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        guard recognizer?.isAvailable == true else {
            print("⚠️ [Speech] Recognizer unavailable for locale \(Locale.current.identifier)")
            return
        }
        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Use Apple's servers for speed; falls back to on-device automatically
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request
        liveTranscript = ""
        isStreaming = true

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
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

    // MARK: - Foundation Models smart formatting

    /// Post-processes a transcript with Apple Intelligence: adds punctuation structure,
    /// detects lists/code/tech terms, removes fillers, adds paragraph breaks.
    /// Returns the original string unchanged if formatting fails or the model is unavailable.
    func formatWithAI(_ transcript: String) async -> String {
        // Skip very short notes — nothing meaningful to clean
        guard transcript.split(separator: " ").count > 8 else { return transcript }

        guard #available(iOS 26.0, *) else { return transcript }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return transcript }

        do {
            let session = LanguageModelSession(instructions: """
                You are a dictation cleanup engine. Transform raw speech-to-text output into clean written text that reads as if the user typed it carefully. Return ONLY the cleaned text — no commentary, no explanation, no preamble.

                PRESERVE MEANING EXACTLY. Never add content, never summarise, never rephrase the user's ideas.

                FILLER WORD REMOVAL:
                Remove: um, uh, er, ah, hmm, you know, I mean (when stalling), basically, literally (when not emphatic), kind of, sort of (when not hedging), "so" at the very start of a sentence when stalling, "well" at the start when stalling, "let me think", "how do I say this".
                Keep "like" when it means comparison or preference ("I like this", "it looks like rain"). Keep "right" when it's a genuine question tag ("that's correct, right?"). Keep "actually" when it introduces contrast. Keep "kind of" / "sort of" when they're genuine hedges ("I'm sort of worried about this"). When uncertain, keep the word — over-removal sounds robotic.

                SELF-CORRECTION RESOLUTION:
                People revise themselves mid-speech. Always resolve to the final intended version.
                - Explicit markers: "X no Y" → Y, "X wait Y" → Y, "X sorry Y" → Y, "X I mean Y" → Y, "X actually Y" → Y, "X scratch that Y" → Y.
                - False starts: "I think we should we need to fix this" → "I think we need to fix this".
                - Repeated words: "the the meeting" → "the meeting", "I I think" → "I think".
                - Multiple corrections: "three no four no five people" → "five people" (take the last).
                - Do NOT collapse genuine alternatives: "we could do A or B" → keep both. "it's due Friday or Monday I'm not sure" → keep both. The signal for a correction is a correction marker (no, wait, sorry, scratch that) or a structural restart — not just "or".

                PUNCTUATION:
                Add all punctuation a careful writer would include: periods, question marks, commas (clause separators, list separators, after introductory phrases), colons before lists, em dashes for parenthetical asides. Use exclamation marks only when tone clearly implies excitement. If the user says "period", "comma", "question mark", "new paragraph" etc. at a natural sentence boundary, execute the command rather than printing the word.

                CAPITALISATION:
                Capitalise sentence-initial words, the word "I", proper nouns (names, places, organisations, products, days, months), and standard acronyms (API, iOS, SQL, etc.). Do not over-capitalise common nouns.

                NUMBER AND TIME FORMATTING:
                - Spell out zero–nine in prose; use digits for 10 and above.
                - Times: "three pm" → "3 PM", "three thirty" → "3:30", "half past two" → "2:30", "quarter to five" → "4:45".
                - Dates: "march fifteenth" → "March 15", capitalise day and month names.
                - Currency: "twenty dollars" → "$20", "five hundred bucks" → "$500".
                - Percentages: "fifty percent" → "50%".
                - Homophones: resolve their/there/they're, your/you're, its/it's, to/too/two, then/than by grammatical role. "would of" → "would have", "could of" → "could have".

                PARAGRAPH BREAKS:
                For short notes (1–3 sentences), use a single paragraph. For longer notes, insert a paragraph break at clear topic shifts. If the user says "new paragraph", execute it.

                NEVER DO:
                - Add content the user did not say.
                - Summarise or shorten the note.
                - Add greetings, sign-offs, or transition phrases the user didn't speak.
                - Add markdown formatting (bold, headers) unless the user clearly dictated a list or structure.
                - Explain what you changed.
                - Output anything except the cleaned text.
                """)
            let response = try await session.respond(to: transcript)
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

    /// Returns true if the model response looks like a refusal, leaked instructions, or is completely off-topic.
    private static func isGarbageResponse(_ response: String, comparedTo original: String) -> Bool {
        let lower = response.lowercased()

        // Refusal openers
        let refusalPrefixes = [
            "i'm sorry", "i am sorry", "i cannot", "i can't", "as a chatbot",
            "as a language model", "as an ai", "certainly!", "sure!", "of course!",
            "i'd be happy", "i would be happy", "i apologize"
        ]
        if refusalPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }

        // Leaked instruction phrases — verbatim strings from our own system prompt
        let leakedPhrases = [
            "filler word removal",
            "self-correction resolution",
            "preserve meaning exactly",
            "never add content",
            "dictation cleanup engine",
            "return only the cleaned text",
            "paragraph breaks"
        ]
        if leakedPhrases.contains(where: { lower.contains($0) }) { return true }

        // Response is more than 4x the length of the input — model hallucinated
        if response.count > original.count * 4 { return true }

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

        // 1. SFSpeechRecognizer — instant result accumulated during recording
        let liveTranscript = await finishStreaming()
        if !liveTranscript.isEmpty {
            print("⚡ [Speech] Instant result (\(liveTranscript.count) chars)")
            return liveTranscript
        }

        // 2. Deepgram nova-2 — if SFSpeechRecognizer came back empty (e.g. no network on Apple's servers)
        do {
            let transcript = try await transcribeViaDeepgram(fileURL: fileURL)
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

        let options = DecodingOptions(task: .transcribe, language: nil, withoutTimestamps: true)
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("✅ [WhisperKit] Done: \(text.prefix(80))")
        return text
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

enum TranscriptionError: Error {
    case modelLoadFailed
    case inferenceFailed
    case deepgramFailed
    case emptyTranscript
}
