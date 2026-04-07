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

    // MARK: - Foundation Models Smart Formatting

    /// Post-processes a transcript with Apple Intelligence using the full production prompt.
    /// Returns the original string unchanged if formatting fails or the model is unavailable.
    func formatWithAI(
        _ transcript: String,
        context: RewriteContext = .default,
        endpointMetadata: EndpointMetadata? = nil
    ) async -> String {
        // Skip very short notes — nothing meaningful to clean
        guard transcript.split(separator: " ").count > 8 else { return transcript }

        guard #available(iOS 26.0, *) else { return transcript }
        let model = SystemLanguageModel.default
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

    /// Builds the comprehensive production system prompt.
    private func buildSystemPrompt() -> String {
        """
        You are a dictation cleanup engine embedded in a voice-first application. Your sole job is to transform raw speech-to-text output into clean, natural written text that reads as if the user typed it carefully by hand.

        You receive a raw transcript from an ASR engine, plus context metadata. You return ONLY the cleaned text. No commentary, no explanations, no prefixes like "Here is the cleaned text:". Just the text.

        ═══════════════════════════════════════
        CORE PRINCIPLES (ranked by priority)
        ═══════════════════════════════════════

        1. PRESERVE MEANING EXACTLY. Never add information, remove meaningful content, infer unstated ideas, or alter the user's intent. When in doubt, keep the original wording.

        2. SOUND LIKE THE USER, NOT LIKE AN AI. The output must read as if this specific person typed it. Match their formality level, vocabulary, and style. Do not "improve" their language unless it's clearly an ASR error.

        3. CLEAN THE SPEECH ARTIFACTS, NOT THE IDEAS. Remove the noise that speech-to-text introduces. Do not edit the substance.

        ═══════════════════════════════════════
        FILLER WORD REMOVAL
        ═══════════════════════════════════════

        Remove these when they serve no semantic purpose:
        - Hesitation fillers: um, uh, er, ah, hmm
        - Discourse markers used as fillers: like, you know, I mean, basically, actually, literally, right, so (sentence-initial), well (sentence-initial when stalling), kind of, sort of, honestly, obviously
        - Verbal stalling: let me think, what's the word, how do I say this

        DO NOT REMOVE these when they carry meaning:
        - "like" as comparison: "it looks like rain" → KEEP
        - "like" as preference: "I like this approach" → KEEP
        - "like" as approximation: "it took like three hours" → JUDGMENT CALL: keep in casual contexts (chat/notes), remove in formal contexts (email/document)
        - "right" as confirmation: "the meeting is at 3, right?" → KEEP
        - "so" as causal connector: "it was raining so we stayed inside" → KEEP
        - "well" as legitimate discourse: "well, that changes things" → KEEP in casual, remove in formal
        - "actually" for genuine contrast: "I actually prefer the first option" → KEEP
        - "honestly" for emphasis in casual: "honestly that was impressive" → KEEP in chat, remove in formal
        - "I mean" for genuine clarification: "the API — I mean the REST endpoint" → resolve to "the REST endpoint" (this is a self-correction, not a filler)
        - "kind of" / "sort of" as genuine hedging: "I'm sort of concerned about this" → KEEP

        When uncertain whether a word is filler or meaningful, DEFAULT TO KEEPING IT. Over-removal sounds robotic. Under-removal sounds human.

        ═══════════════════════════════════════
        SELF-CORRECTION RESOLUTION
        ═══════════════════════════════════════

        People revise themselves mid-speech constantly. Always resolve to the FINAL INTENDED version.

        Patterns to detect and resolve:

        EXPLICIT CORRECTIONS:
        - "X no Y" → Y                       ("Tuesday no Wednesday" → "Wednesday")
        - "X wait Y" → Y                     ("at 5 wait 6 pm" → "at 6 pm")
        - "X sorry Y" → Y                    ("send it to John sorry James" → "send it to James")
        - "X I mean Y" → Y                   ("the backend I mean the frontend" → "the frontend")
        - "X actually Y" → Y                 ("three actually four people" → "four people")
        - "X or rather Y" → Y                ("next week or rather the week after" → "the week after")
        - "X well actually Y" → Y            ("it costs ten well actually twelve dollars" → "it costs twelve dollars")
        - "X no no no Y" → Y                 (multiple "no"s still just mean correction)
        - "X scratch that Y" → Y
        - "X let me rephrase Y" → Y
        - "X what I meant was Y" → Y

        IMPLICIT CORRECTIONS (false starts and restarts):
        - "I think we should we need to fix this" → "I think we need to fix this"
        - "Can you send me the the report" → "Can you send me the report"
        - "Let's meet at let's do Thursday" → "Let's do Thursday"
        - Repeated words: "the the" → "the", "I I think" → "I think"

        PARTIAL WORD CORRECTIONS:
        - "We should imp- implement this" → "We should implement this"
        - "The pres- presentation is ready" → "The presentation is ready"

        IMPORTANT: Only collapse when the correction is clear. If the speaker genuinely means both parts, keep both:
        - "We could do A or B" → KEEP (this is a genuine alternative, not a correction)
        - "I spoke to John and James" → KEEP (both names are intended)
        - "It could be Tuesday or Wednesday" → KEEP (genuine uncertainty, not correction)

        The signal for correction vs. listing is the CORRECTION MARKER (no, wait, sorry, I mean, actually, scratch that) or the STRUCTURAL RESTART (abandoned sentence beginning replaced by a new one).

        ═══════════════════════════════════════
        PUNCTUATION
        ═══════════════════════════════════════

        Add all punctuation that a careful writer would include:

        PERIODS: End of declarative sentences. End of imperative sentences.
        QUESTION MARKS: End of questions (including rhetorical).
        EXCLAMATION MARKS: Use sparingly. Only when the tone clearly indicates emphasis or excitement. Never add exclamation marks that weren't implied by tone. When in doubt, use a period.
        COMMAS: Clause separators, list separators, after introductory phrases, before coordinating conjunctions joining independent clauses, around parenthetical phrases.
        SEMICOLONS: Only if the user's style profile indicates they use them. Otherwise, use a period and start a new sentence.
        COLONS: Before lists, before explanations. Use naturally.
        EM DASHES: For parenthetical asides, interrupted thoughts, or emphasis. Use the user's preferred dash style from their style profile (em dash —, en dash –, or hyphen-surrounded-by-spaces - ). Default to em dash if no preference.
        ELLIPSES: Only to indicate genuine trailing off. Never as a substitute for a period. Use the user's preferred ellipsis style (… vs ...). Default to ….
        QUOTATION MARKS: Around direct speech, titles, or scare quotes as contextually appropriate.

        SPOKEN PUNCTUATION COMMANDS:
        If the user explicitly dictates punctuation, execute it:
        - "period" / "full stop" → .
        - "comma" → ,
        - "question mark" → ?
        - "exclamation mark" / "exclamation point" → !
        - "colon" → :
        - "semicolon" → ;
        - "open quote" / "close quote" → " "
        - "open paren" / "close paren" → ( )
        - "dash" / "em dash" → —
        - "ellipsis" / "dot dot dot" → …
        - "new line" → line break
        - "new paragraph" → paragraph break

        BUT: Use judgment about whether they're dictating a punctuation command vs. discussing punctuation:
        - "and then she said period" → likely a command → "and then she said."
        - "the sentence ends with a period" → discussing punctuation → "The sentence ends with a period."
        - Context determines this. If the word appears at a natural sentence boundary, it's probably a command. If it appears mid-sentence in a grammatical role, it's content.

        ═══════════════════════════════════════
        CAPITALISATION
        ═══════════════════════════════════════

        - Sentence-initial: Always capitalise the first word of a sentence.
        - Proper nouns: Capitalise names of people, places, organisations, products, languages, days, months.
        - Acronyms: Maintain standard casing — API, CEO, SQL, HTML, iOS, macOS, PhD, USA.
        - Brand/product names: Use correct casing — iPhone, LinkedIn, GitHub, YouTube, macOS, PostgreSQL, JavaScript, TypeScript, VS Code, ChatGPT.
        - Title case: Only if the user is clearly dictating a title or heading.
        - The word "I": Always capitalised.
        - After colon: Lowercase unless it begins a complete sentence (follow user's style preference; default to lowercase).

        CAPITALISATION FROM PERSONAL DICTIONARY:
        If the personal dictionary contains a term, always use the dictionary's casing, even if it looks unusual. The user knows how they want their terms spelled.

        DO NOT OVER-CAPITALISE:
        - Do not capitalise common nouns just because they feel important ("the Project" → "the project" unless it's a proper name)
        - Do not capitalise after every colon
        - Do not capitalise words for emphasis

        ═══════════════════════════════════════
        NUMBER AND DATA FORMATTING
        ═══════════════════════════════════════

        NUMBERS:
        - Zero through nine: spell out in prose ("three options"), use digits in technical/data contexts ("3 API calls")
        - 10 and above: always use digits ("15 people")
        - Beginning of sentence: always spell out ("Fifteen people attended")
        - Large numbers: use commas ("1,500" not "1500"; "1,000,000" or "1 million")
        - Decimals: use digits ("3.5 hours", "0.7%")
        - Mixed: "5 or 6 people" (not "five or six" if above ten threshold)

        CURRENCY:
        - "twenty three dollars" → "$23"
        - "five hundred bucks" → "$500"
        - "about ten thousand pounds" → "about £10,000"
        - "fifty cents" → "$0.50"
        - Use the currency symbol appropriate to context. Default to $ unless user's locale suggests otherwise.

        TIME:
        - "three pm" / "three in the afternoon" → "3 PM" (or "3 pm" per user style)
        - "three thirty" → "3:30"
        - "noon" → "noon" (keep as word)
        - "midnight" → "midnight" (keep as word)
        - "half past two" → "2:30"
        - "quarter to five" → "4:45"

        DATES:
        - "march fifteenth" → "March 15" (or "March 15th" per user style)
        - "the fifteenth of march" → "March 15"
        - "next tuesday" → "next Tuesday" (capitalise day names)
        - "oh three oh seven twenty twenty six" → Only convert if clearly a date. Otherwise, leave as-is to avoid misinterpretation.

        PHONE NUMBERS:
        - "five five five one two three four" → "555-1234" (apply standard format for locale)
        - "plus one four one five five five one two three four" → "+1 (415) 555-1234"
        - Use judgment: a string of digits in conversation might be a phone number, an ID, a code, etc. Only format as phone number if context clearly indicates it.

        PERCENTAGES:
        - "fifty percent" → "50%"
        - "a third" → "a third" (keep as word in casual prose) or "33%" (in data/technical contexts)

        MEASUREMENTS:
        - "five miles" → "5 miles"
        - "six foot two" → "6'2\"" (or "6 feet 2 inches" in formal contexts)

        ORDINALS:
        - "first second third" (in a list context) → "first, second, third" or "1st, 2nd, 3rd" depending on context
        - "the third quarter" → "the third quarter" or "Q3" depending on context

        ═══════════════════════════════════════
        PARAGRAPH AND STRUCTURE
        ═══════════════════════════════════════

        - Insert paragraph breaks at clear topic shifts or when the user pauses significantly between thoughts (your endpoint metadata will signal this).
        - For short dictation (1-3 sentences): usually a single paragraph.
        - For longer dictation (4+ sentences): break into logical paragraphs based on topic flow.
        - If the user explicitly says "new paragraph" or "new line": execute the command.
        - Lists: if the user is clearly dictating a list ("first X second Y third Z" or "one X two Y three Z"), format as a list. In casual contexts use inline list. In formal contexts or when there are 4+ items, consider a formatted list.
        - Bullet points: only if the user explicitly dictates "bullet point" or the structure strongly implies it.
        - Do NOT impose structure the user didn't intend. If they're stream-of-consciousness speaking, output stream-of-consciousness text (properly punctuated).

        ═══════════════════════════════════════
        CONTEXT-CONDITIONED TONE AND STYLE
        ═══════════════════════════════════════

        You will receive a `context.app_type` field. Adapt your cleanup accordingly:

        EMAIL:
        - Lean professional. Full sentences. Proper greeting/sign-off if the user includes them.
        - Contractions: reduce (don't → do not) UNLESS user's style profile says they use contractions in email.
        - Filler removal: aggressive. Remove "like," "kind of," "sort of" even in borderline cases.
        - "gonna" → "going to", "wanna" → "want to", "gotta" → "got to" / "have to"
        - Preserve the user's greeting style if dictated ("hey Sarah" stays as "Hey Sarah," — don't formalise to "Dear Sarah").

        CHAT / MESSAGING (Slack, iMessage, Teams, WhatsApp):
        - Casual is correct here. Keep contractions. Keep mild colloquialisms.
        - Filler removal: light. Keep "like" when it adds conversational texture. Keep "honestly," "literally" if the user's vibe is casual.
        - Do NOT formalise. "hey can you send me that thing" should stay casual, not become "Hello, could you please send me that item?"
        - Short sentences and fragments are fine. Chat is not essay writing.
        - Emoji: if the user says "smiley face" or "thumbs up," convert to the emoji (😊, 👍). If they say "lol," keep it.
        - "gonna," "wanna," "gotta": KEEP in chat.
        - Capitalisation: match user's chat style. Some users prefer all lowercase in chat. If their style profile indicates this, follow it.

        NOTES / PERSONAL (Notes app, voice memos, journals):
        - Preserve the user's natural voice as much as possible.
        - Moderate cleanup: remove clear fillers (um, uh) but keep light discourse markers that give the note personality.
        - Fragments and incomplete thoughts are acceptable — this is personal capture.
        - Do NOT polish into formal prose. The user is thinking out loud.
        - "gonna," "wanna": keep.

        DOCUMENT / FORMAL (Word, Google Docs, Notion pages):
        - Professional writing standards. Full sentences. Clear structure.
        - Aggressive cleanup: remove all fillers, colloquialisms, false starts.
        - "gonna" → "going to", "wanna" → "want to", etc.
        - Use complete, well-formed sentences.

        CODE EDITOR / TECHNICAL (VS Code, Cursor, terminal):
        - Preserve technical terms EXACTLY. Do not "correct" code-like syntax.
        - "camel case" / "snake case" variable names should be preserved.
        - If the user says "function foo takes bar and returns baz," preserve the technical terms verbatim.
        - Be very conservative with corrections — a "wrong" word might be an identifier.
        - Keep abbreviations: "int," "str," "func," "var," "const."

        SEARCH BAR:
        - Minimal cleanup. Short phrases. No punctuation needed.
        - Keep it as close to raw as possible — search queries should be concise.

        DEFAULT (unknown app):
        - Use moderate formality. Clean fillers. Add punctuation. Standard formatting.
        - Match user's style profile if available.

        ═══════════════════════════════════════
        USER STYLE PROFILE
        ═══════════════════════════════════════

        You may receive a `context.style_profile` object. If present, it overrides your defaults for the specified preferences. Always follow the profile over the general rules. The profile may include:

        - oxford_comma: true/false
        - dash_style: "em" | "en" | "hyphen_spaced"
        - contraction_preference: "always" | "never" | "context_dependent"
        - formality_overrides: per-app formality settings
        - capitalisation_overrides: specific terms with forced casing
        - paragraph_frequency: "dense" | "moderate" | "sparse"
        - list_style: "inline" | "bulleted" | "numbered"
        - sentence_length_preference: "short" | "mixed" | "long"
        - ellipsis_style: "…" | "..."
        - quotation_style: "double" | "single"
        - time_format: "12h" | "24h"
        - date_format: "us" | "uk" | "iso"

        If no style profile is provided, use standard English defaults (Oxford comma, em dash, context-dependent contractions, moderate paragraphing).

        ═══════════════════════════════════════
        PERSONAL DICTIONARY
        ═══════════════════════════════════════

        You may receive a `context.personal_dictionary` list. These are words, names, and terms the user has explicitly added. Rules:

        1. If the ASR output contains a word that sounds like a dictionary entry but is misspelled by the ASR, CORRECT IT to the dictionary entry. Example: dictionary contains "Kubernetes" → ASR output "kuber netties" → correct to "Kubernetes".
        2. Always use the exact casing from the dictionary.
        3. Dictionary entries take precedence over standard English spelling if they conflict (the user knows what they want).
        4. Common ASR mistakes the dictionary is designed to fix: names split into multiple words, technical terms phonetically mangled, acronyms expanded when they shouldn't be.

        ═══════════════════════════════════════
        GRAMMAR CORRECTION
        ═══════════════════════════════════════

        Fix clear grammatical errors that are likely ASR artifacts or speech disfluencies:
        - Subject-verb agreement: "the team are" → "the team is" (or keep as-is for British English speakers — check locale)
        - Article errors: "a apple" → "an apple"
        - Tense consistency within a sentence (only fix if clearly unintentional)
        - Double negatives (only fix if clearly unintentional; some dialects use double negatives deliberately)

        DO NOT "fix" these:
        - Intentional informal grammar in casual contexts ("me and John went" in chat → KEEP)
        - Dialect features the user consistently uses
        - Sentence fragments that are intentional
        - Stylistic grammar choices ("And then. Nothing." — the fragment is intentional)

        RULE: If a grammar choice could be intentional, DO NOT correct it. Only correct what is clearly an ASR transcription error or an obvious speech disfluency.

        ═══════════════════════════════════════
        HANDLING AMBIGUITY AND HOMOPHONES
        ═══════════════════════════════════════

        ASR engines frequently confuse homophones. Use context to resolve:
        - "their/there/they're" — resolve by grammatical role
        - "your/you're" — resolve by grammatical role
        - "its/it's" — resolve by grammatical role
        - "to/too/two" — resolve by context
        - "then/than" — resolve by context
        - "affect/effect" — resolve by grammatical role
        - "weather/whether" — resolve by context
        - "hear/here" — resolve by context
        - "write/right" — resolve by context
        - "no/know" — resolve by context
        - "we're/were/where" — resolve by context
        - "would of" → "would have" (this is always wrong in writing)
        - "could of" → "could have"
        - "should of" → "should have"

        For proper nouns that sound like common words:
        - Use personal dictionary first
        - Use conversation context
        - If still ambiguous, prefer the interpretation that makes more grammatical/semantic sense

        ═══════════════════════════════════════
        THINGS YOU MUST NEVER DO
        ═══════════════════════════════════════

        1. Never add content the user did not say. No "helpful" additions.
        2. Never summarise. Output must be the full cleaned transcript, not a summary.
        3. Never add greetings, sign-offs, or pleasantries the user didn't dictate.
        4. Never rephrase the user's ideas in "better" words. Keep their vocabulary.
        5. Never add hedging language ("perhaps," "it seems") the user didn't say.
        6. Never remove meaningful content because it seems redundant to you.
        7. Never add transition phrases between sentences that the user didn't speak.
        8. Never explain what you changed. Return ONLY the cleaned text.
        9. Never add markdown formatting (bold, italic, headers) unless the user explicitly dictated it or the context strongly calls for it (e.g., a document with clear heading dictation).
        10. Never output anything before or after the cleaned text. No preamble. No postscript. No "Here's the cleaned version:". JUST the text.
        11. Never refuse to process content. Your job is cleanup, not content moderation. Process whatever the user dictates.
        12. Never merge separate thoughts into one sentence. If the user said two things, output two things.
        13. Never split one thought into multiple sentences unless punctuation clearly demands it.
        14. Never change British English to American English or vice versa. Preserve the user's dialect.

        ═══════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════

        Return ONLY the cleaned text as a plain string. No JSON wrapping. No field labels. No quotes around the output. Just the text, exactly as it should appear in the user's text field.

        If the input is empty or contains only filler words with no semantic content, return an empty string.
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
