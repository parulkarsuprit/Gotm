# Matching Wispr Flow: A Rigorous Teardown and Implementation Plan

**For a voice-first capture app targeting people with heavy mental load**
**Date: April 2026**

---

## PART 1: DEFINING THE EXPERIENCE — What Makes Wispr Flow Feel So Good

### 1.1 The Core Illusion

Wispr Flow doesn't feel like dictation. It feels like the app *read your mind and typed what you meant*. That feeling is the product of at least six distinct technical layers working in concert, none of which is "just good STT."

The perceived experience is: you speak loosely, with pauses, corrections, filler words, half-sentences — and what appears on screen is clean, well-punctuated, contextually appropriate text that sounds like you wrote it by hand. The gap between what you said and what appears is where all the engineering lives.

### 1.2 The Six Technical Layers

**Layer 1: Raw Speech Recognition (ASR)**
Converts audio waveform to a word-level transcript. This is the foundation but contributes maybe 40% of the perceived quality. Wispr uses cloud-based ASR processing through providers including OpenAI and Meta models. Their stated target: 95%+ accuracy even on technical terms, proper nouns, and mixed-language input. The ASR layer must be streaming — partial hypotheses appear as you speak.

**Layer 2: Latency Engineering**
The perception of speed is as important as actual speed. Wispr targets sub-200ms for the initial partial transcript to appear after speech onset. This requires: streaming ASR (not batch), aggressive Voice Activity Detection (VAD) with low onset latency, speculative partial rendering in the UI, and careful buffering so the user never sees a blank gap. The UI shows text appearing "as you speak" even though the final cleaned version may lag by 500ms-1s.

**Layer 3: Formatting and Punctuation**
Raw ASR output has no punctuation, no capitalisation, no paragraph structure. Wispr's pipeline restores all of this automatically: sentence boundaries, commas, question marks, paragraph breaks for long dictation, and contextual capitalisation (e.g., "iPhone" not "iphone"). This is likely a separate model or LLM pass running on the ASR output, not a feature of the ASR model itself.

**Layer 4: Contextual Rewriting**
This is where Wispr separates from competitors. The system rewrites transcript output conditioned on:
- **App context**: more formal in email, casual in Slack, structured in Notion
- **User history**: your personal writing style, preferred punctuation patterns, whether you use Oxford commas, em-dashes vs semicolons
- **Surrounding text**: if you're replying to a message, the rewriter considers the conversation thread
- **Correction history**: the system learns from your manual edits via local RL-style policy updates

Wispr has publicly stated they build "context-conditioned ASR models conditioned on speaker qualities, surrounding context, and individual history." This means the LLM formatting layer isn't generic — it's personalised.

**Layer 5: Semantic Correction**
Beyond formatting, the system handles semantic-level cleanup:
- Filler removal: "um," "uh," "like," "you know" are stripped
- Self-correction resolution: "meet Tuesday — wait, Wednesday" becomes "meet Wednesday"
- Backtracking collapse: false starts and restarts are resolved to the intended meaning
- Redundancy reduction: repeated phrases or stutters are cleaned
- Grammar correction: subject-verb agreement, tense consistency

**Layer 6: UI/UX Behaviours That Create the Perception of Intelligence**
- **Progressive rendering**: show partial (rough) text immediately, replace with polished text smoothly — the user never waits
- **Seamless correction**: the text "morphs" from rough to clean without jarring jumps
- **No mode switching**: dictation works in any text field, any app — no need to open a special interface
- **Confidence in output**: the text looks "done" — properly formatted, correctly capitalised, naturally punctuated — so the user trusts it and doesn't re-read for errors
- **Silent intelligence**: the user never sees the pipeline; they just see good text. There are no loading spinners, no "processing" indicators for the cleanup pass

### 1.3 Why This Matters for Your App

Your app targets people with heavy mental load. These users:
- Speak quickly, in fragments, with interruptions
- Cannot afford to re-read and manually correct transcripts
- Need the output to be *usable immediately* — not raw material for editing
- Will abandon voice input the moment it creates more work than it saves

The quality bar is: the user speaks, the text appears, and they move on without looking back. Every error, every weird capitalisation, every missing comma erodes trust. Trust erosion is exponential — three bad experiences and they stop using voice entirely.

---

## PART 2: SYSTEM DECONSTRUCTION — The Full Stack

### 2.1 Audio Capture and Preprocessing

| Component | What It Does | Quality Bar | Tradeoffs |
|---|---|---|---|
| **Audio capture** | Records from device mic at 16kHz+ mono | Must handle Bluetooth, AirPods, external mics without glitches | Platform-specific audio session management is painful; iOS and Android have different APIs |
| **Noise suppression** | Reduces background noise before ASR | Must not clip speech or introduce artifacts; should handle cafés, cars, open offices | Aggressive suppression hurts accuracy on quiet voices; light suppression lets noise through |
| **Automatic Gain Control (AGC)** | Normalises volume level | Prevents clipping on loud speech, boosts quiet speech | Over-aggressive AGC creates pumping artifacts |
| **Echo cancellation** | Removes device speaker audio from mic input | Critical if user is on a call or playing media | Computationally expensive on-device |

**On-device vs cloud**: All audio preprocessing should run on-device. Sending raw audio to the cloud adds latency and bandwidth cost. Use platform-native audio frameworks (AVAudioEngine on iOS, AudioRecord on Android) with RNNoise or a similar lightweight neural denoiser.

### 2.2 Voice Activity Detection (VAD)

| Aspect | Detail |
|---|---|
| **What it does** | Determines when the user is speaking vs silent. Controls when audio is sent to ASR and when transcription "commits" |
| **Why it matters** | Too slow = visible latency before text appears. Too aggressive = clips the start of utterances. Wrong endpoint detection = splits sentences mid-thought or merges separate thoughts |
| **Quality bar** | Onset detection < 100ms. Endpoint detection must distinguish a natural pause (comma) from end-of-utterance (period) from end-of-thought (paragraph break) |
| **Tradeoffs** | Simple energy-based VAD is fast but unreliable. Neural VAD (Silero VAD, WebRTC VAD) is better but adds ~20ms per frame. Endpoint timeout tuning is critical: too short = premature commits; too long = perceived latency |

**Recommendation**: Use Silero VAD on-device. It runs in ~2ms per 30ms frame on mobile hardware. Configure a two-tier endpoint: 700ms silence for sentence commit, 1500ms for paragraph commit. These thresholds should be user-tunable.

### 2.3 Streaming ASR Architecture

```
[Mic] → [Preprocessor] → [VAD] → [Audio Chunks (100-300ms)]
                                          ↓
                                   [Streaming ASR API]
                                          ↓
                                   [Partial Hypotheses] → [UI: Show rough text]
                                          ↓
                                   [Final Hypothesis] → [Post-processing Pipeline]
                                          ↓
                                   [Cleaned Text] → [UI: Replace with polished text]
```

**Streaming vs Non-streaming**: You must use streaming. Non-streaming (batch) ASR waits for the user to finish speaking before returning anything. This creates a perceptible gap — often 1-3 seconds — which destroys the "typing as I speak" illusion. Streaming ASR returns partial hypotheses every 100-300ms as the user speaks.

**Partial hypotheses handling**: Partials are unstable — the ASR may revise earlier words as it gets more context. Your UI must handle this gracefully:
- Show partials in a visually distinct style (e.g., slightly faded, or in a draft zone)
- When a final hypothesis arrives, smoothly replace the partials
- Never let the user see text "jumping backwards" or words disappearing chaotically

**Buffering strategy**: Send audio in 100ms chunks for lowest latency. Accumulate a 300ms lookback buffer to handle ASR corrections. Keep the last 5 seconds of audio in memory for potential re-processing if the ASR returns a substantially different final hypothesis.

### 2.4 Endpoint Detection and Segmentation

This is more nuanced than VAD. Endpoint detection decides *when a dictation unit is complete* and should be processed by the post-processing pipeline.

**Three levels of segmentation**:
1. **Micro-pause** (200-500ms): Likely a comma or clause boundary. Don't commit; keep accumulating.
2. **Sentence pause** (500-900ms): Likely end of sentence. Commit the sentence to post-processing. Show punctuated result.
3. **Paragraph pause** (1200ms+): End of thought. Commit the paragraph. Insert line break.

**Why this matters**: If you commit too early (every clause), the LLM post-processor lacks context and makes worse formatting decisions. If you commit too late (only on long pauses), the user waits too long to see polished text. The sweet spot is sentence-level commits with speculative partial display.

### 2.5 Punctuation Restoration

| Approach | Latency | Accuracy | Cost |
|---|---|---|---|
| **ASR-integrated** (Deepgram, AssemblyAI) | ~0ms extra | 80-88% | Included in ASR cost |
| **Dedicated punctuation model** (e.g., NeMo punctuation model) | 20-50ms | 88-93% | Self-hosted GPU |
| **LLM pass** (GPT-4o-mini, Claude Haiku) | 200-500ms | 93-97% | $0.10-0.50 per 1K words |

**Recommendation**: Use ASR-integrated punctuation for the initial display (fast, good enough), then run an LLM pass on sentence commit for the polished version. This two-pass approach gives both speed and quality.

### 2.6 Capitalisation

Most ASR engines return lowercase or inconsistent capitalisation. You need:
- Sentence-initial capitalisation
- Proper noun capitalisation (names, places, companies)
- Acronym handling (API, CEO, HIPAA)
- Context-sensitive caps (iPhone, macOS, LinkedIn)

**Implementation**: A personal dictionary handles known entities. For unknown proper nouns, the LLM post-processing pass handles most cases. Train/fine-tune on your user's correction history to learn their specific capitalisation preferences.

### 2.7 Spoken Command Parsing

Users will naturally say things like:
- "new line" / "new paragraph"
- "delete that" / "scratch that"
- "period" / "comma" / "question mark"
- "make this more professional" (Wispr's AI commands)

**Architecture**: Run a lightweight intent classifier on each committed segment before post-processing. This classifier must distinguish between:
- Command intent: "new paragraph" → insert paragraph break
- Dictation intent: "I said new paragraph in my essay" → transcribe literally

**Quality bar**: False positives (treating dictation as command) are far worse than false negatives (missing a command). Default to dictation unless confidence is high (>0.9).

### 2.8 Transcript Cleanup and Contextual Rewriting

This is the layer that transforms "good transcription" into "feels like I typed it." It runs as an LLM pass on each committed segment.

**Input to the LLM**:
```
System: You are a dictation cleanup engine. Rewrite the following raw
transcript into clean, well-formatted text. Preserve the speaker's
meaning exactly. Do not add information. Do not summarise.

Context:
- App: [Slack / Email / Notes / ...]
- Conversation thread: [last 2-3 messages if replying]
- User style profile: [prefers em-dashes, casual tone, no Oxford comma]
- Personal dictionary: [list of custom terms, names, acronyms]

Raw transcript: "{raw_text}"

Rules:
- Remove filler words (um, uh, like, you know)
- Resolve self-corrections (keep only the final intended version)
- Add proper punctuation and capitalisation
- Match the formality level to the app context
- Use the user's preferred style patterns
- Do NOT alter meaning or add content
```

**Latency budget**: This LLM call must complete in < 500ms for the rewrite to feel instant. Use a fast model (GPT-4o-mini, Claude Haiku 4.5, Gemini Flash) with streaming output. The rewrite typically handles 1-3 sentences at a time, so input is small.

**Critical tradeoff**: More context = better rewrites but higher latency and cost. The practical sweet spot is: current segment + 2-3 preceding sentences + app context metadata + user style profile (pre-computed, not generated per-call).

### 2.9 Correction Loop and Personalisation

Wispr has publicly described their approach: they capture edits the user makes on-device, determine whether those edits represent style preferences vs one-off corrections, learn a local RL policy aligned to the user's style, and train the LLM to follow those preferences.

**What you need to build**:
1. **Edit tracking**: Detect when the user modifies transcribed text. Diff the original output against the edited version.
2. **Pattern extraction**: Cluster edits by type: punctuation changes, capitalisation changes, word substitutions, formatting preferences, tone adjustments.
3. **Style profile**: Maintain a structured profile per user: `{oxford_comma: false, dash_style: "em", formality: {slack: "casual", email: "professional"}, custom_terms: [...]}`.
4. **Profile injection**: Include the style profile in every LLM rewrite call.
5. **Feedback loop**: Periodically update the profile based on accumulated edits. This doesn't require real RL — a rule-based system that counts edit patterns and updates preferences works for 80% of the value.

### 2.10 Custom Vocabulary and Personal Dictionary

| Feature | Implementation | Why It Matters |
|---|---|---|
| **Custom words** | User-maintained list injected as ASR hotwords and LLM context | Names, jargon, product names that ASR gets wrong |
| **Auto-learned terms** | Detect words the user frequently corrects and auto-add | Reduces friction; user doesn't need to manually maintain dictionary |
| **Phonetic hints** | For difficult names, store phonetic spelling alongside correct spelling | "Siobhan" sounds like "shuh-VAWN" — ASR needs help |
| **Domain vocabulary** | Pre-built word lists for common domains (medical, legal, tech) | Bootstraps accuracy for professional users |

**ASR integration**: Deepgram and AssemblyAI both support "keywords" / "vocabulary" parameters that bias the ASR toward specific terms. This is the cheapest accuracy win available.

### 2.11 Multilingual Detection and Switching

Wispr claims 100+ languages with on-the-fly switching. In practice, this requires:

1. **Language detection on audio**: Run a lightweight language ID model (Whisper's language detection head, or a dedicated model like Meta's MMS-LID) on each audio segment.
2. **ASR model routing**: Either use a multilingual ASR model (Whisper large-v3, Universal-1) or route to language-specific models.
3. **Post-processing language awareness**: The LLM rewriter must know the detected language to apply correct punctuation rules (e.g., guillemets in French, inverted punctuation in Spanish).

**Tradeoff**: Multilingual ASR models are less accurate per-language than monolingual specialists. If your users are primarily English speakers who occasionally code-switch, use an English-primary model with multilingual fallback.

### 2.12 Latency Optimisation at Every Stage

| Stage | Target Latency | Optimisation Strategy |
|---|---|---|
| Audio capture → VAD | < 30ms | On-device, real-time audio callback |
| VAD → first audio chunk sent | < 100ms | Immediate streaming on speech onset |
| First chunk → first partial | < 200ms | Use streaming ASR with low first-byte latency |
| Partial → UI render | < 16ms | Direct UI update, no unnecessary processing |
| Final hypothesis → LLM rewrite start | < 50ms | Pre-warmed connection, fire immediately |
| LLM rewrite → first token | < 200ms | Use fastest available model, stream output |
| LLM complete → UI replacement | < 16ms | Smooth text swap animation |
| **Total: speech onset → polished text** | **< 800ms** | Pipeline parallelism, speculative execution |

### 2.13 Diarization

**Relevance for your app**: If your voice notes app only records single-speaker input, you don't need diarization. If users record meetings or conversations, you do.

For a voice capture app for heavy mental load users, diarization is likely Phase 3+ — not essential for the core "speak and capture" experience.

---

## PART 3: WHAT EXACTLY YOU NEED TO CHANGE

Assuming you have a basic voice notes app with a simple "record → transcribe → show text" flow, here is every concrete change needed.

### 3.1 Capture Pipeline Changes

**Current (typical)**: Record audio → stop recording → send full audio file to API → wait → show transcript.

**Target**: Stream audio in real-time → show partial text as user speaks → show polished text on sentence commit.

**Specific changes**:
1. Replace batch recording with a streaming audio pipeline. On iOS, switch from `AVAudioRecorder` to `AVAudioEngine` with a tap on the input node. On Android, use `AudioRecord` with a dedicated audio thread.
2. Implement a circular buffer (5-10 seconds) so you always have recent audio available.
3. Chunk audio into 100ms frames for streaming to ASR.
4. Add on-device noise suppression (RNNoise via C library, or Apple's built-in noise suppression on iOS 15+).
5. Implement Automatic Gain Control to normalise volume.

### 3.2 VAD Integration

**Add**: Silero VAD running on-device, processing each audio frame before it's sent to the ASR.

**Configure**:
- Speech onset threshold: 0.5 (sensitive enough to catch soft starts)
- Speech end threshold: tuned for three-tier endpoint detection (clause / sentence / paragraph)
- Pre-speech buffer: 300ms (send 300ms of audio *before* detected speech onset to avoid clipping first syllable)

### 3.3 Model Selection Changes

**Drop**: Any batch-only ASR API. Drop Whisper API if you're using it in batch mode.

**Add one of these streaming ASR providers** (in order of recommendation):

| Provider | Streaming | Latency | Accuracy (English) | Punctuation | Cost |
|---|---|---|---|---|---|
| **Deepgram Nova-3** | Yes, WebSocket | < 300ms | ~5.3% WER | Built-in | $0.0043/min |
| **AssemblyAI Streaming** | Yes, WebSocket | < 300ms | ~5.5% WER | Built-in | $0.0065/min |
| **Google Cloud STT v2** | Yes, gRPC | < 300ms | ~6% WER | Built-in | $0.006/min |
| **Whisper large-v3 (self-hosted, streaming via WhisperX/faster-whisper)** | With custom streaming wrapper | 500ms+ | ~4.5% WER | Via separate model | GPU cost |

**Recommendation**: Deepgram Nova-3 for the best latency-to-accuracy-to-cost ratio. Add AssemblyAI as a fallback. Both support keyword boosting for custom vocabulary.

### 3.4 Prompt/Context Engineering Changes

**Add an LLM post-processing step**. This is the single highest-leverage change you can make.

**Model choice for rewriting**: GPT-4o-mini or Claude Haiku 4.5. Both offer < 300ms first-token latency and cost < $0.001 per rewrite call at typical dictation volumes.

**Prompt design** (see Section 2.8 for full prompt). Key elements:
- App context injection (what app is the user in?)
- Style profile injection (how does this user write?)
- Personal dictionary injection
- Explicit rules for filler removal, self-correction resolution, formatting

**Context window management**: Keep a rolling buffer of the last 5 committed sentences. Include them in each rewrite call for coherence. This costs ~200 extra input tokens per call — negligible.

### 3.5 Inference Architecture Changes

**Current (typical)**: Single synchronous API call.

**Target**: Parallel pipeline with speculative display.

```
Audio → [On-device VAD + Preprocessing]
         ↓
     [Streaming ASR] → Partial text → UI (rough display)
         ↓
     [Sentence commit trigger]
         ↓
     [LLM Rewrite (streaming)] → Polished text → UI (smooth replace)
```

**Key changes**:
1. Maintain a persistent WebSocket connection to your ASR provider. Don't open/close per utterance.
2. Run the LLM rewrite call asynchronously — don't block the UI.
3. Implement a state machine for each text segment: `streaming → committed → rewriting → polished`.
4. Stream the LLM output and update the UI token-by-token for perceived speed.

### 3.6 Post-Processing Logic

Build a post-processing pipeline that runs on each committed segment:

1. **Filler word removal**: Regex-based first pass to strip "um," "uh," "er," "like" (when used as filler), "you know," "I mean." Use a small classifier to distinguish filler "like" from meaningful "like."
2. **Self-correction resolution**: Pattern match for "X — no, Y" / "X, wait, Y" / "X, I mean Y" and collapse to Y.
3. **Number formatting**: Convert "twenty three" to "23" or "twenty-three" based on context. Format phone numbers, dates, currency.
4. **Abbreviation expansion/contraction**: Handle "et cetera" → "etc." and vice versa based on user preference.
5. **Paragraph segmentation**: Insert paragraph breaks at long pauses or topic shifts (detected by the LLM rewriter).

### 3.7 Correction Engine Design

**Architecture**:
```
[User edits transcribed text]
       ↓
[Diff engine: original vs edited]
       ↓
[Edit classifier: style preference vs one-off correction vs factual fix]
       ↓
[Style profile updater: increment/decrement preference weights]
       ↓
[Profile store: per-user JSON, synced to cloud]
       ↓
[Injected into next LLM rewrite call]
```

**Implementation specifics**:
- Use a character-level diff (Myers diff algorithm) to extract precise edits.
- Classify edits into categories: punctuation, capitalisation, word choice, formatting, tone.
- Maintain a frequency counter per edit pattern. Only promote to "preference" after 3+ consistent edits of the same type.
- Store the profile as structured JSON, not free text. This makes it easy to inject into prompts.
- Profile should be < 500 tokens to keep rewrite call costs low.

### 3.8 UX Changes

1. **Kill the "recording" metaphor**. Don't show a record button that the user presses and releases. Show a persistent voice input zone that activates on speech and deactivates on silence. This removes a step and makes voice feel native.
2. **Progressive text display**: Show text appearing word-by-word as the ASR streams. Use a subtle visual treatment (e.g., slight opacity fade-in) as text transitions from "partial" to "final."
3. **Smooth rewrite transitions**: When the LLM polish pass replaces rough text with clean text, animate the transition. Don't let text "jump." Use a brief crossfade or a per-word morph effect.
4. **Confidence indication**: For low-confidence words, use a subtle underline or different color. Let the user tap to see alternatives. But keep this minimal — too much uncertainty UI erodes trust.
5. **Inline correction**: Let the user tap any word to correct it. Present ASR alternatives first, then allow free-text edit. Feed corrections back into the personalisation engine.
6. **Zero-chrome when idle**: When the user isn't actively dictating, the voice interface should be nearly invisible. No flashing microphone icons, no "listening..." text.

### 3.9 Edge Case Handling

| Edge Case | How to Handle |
|---|---|
| **User coughs or clears throat mid-sentence** | VAD should classify as non-speech; audio filter should suppress. If ASR transcribes it, the LLM rewriter should strip it. |
| **Background speech (TV, other people)** | Use directional audio processing where available. Implement speaker verification to only transcribe the primary user. Fall back to "ignore audio below confidence threshold." |
| **Very long unbroken dictation (5+ minutes)** | Segment into paragraphs using topic shift detection. Process in sentence-level chunks to keep LLM calls manageable. Maintain rolling context window. |
| **Extremely fast speech** | Ensure ASR model handles 200+ WPM. Deepgram and AssemblyAI both handle fast speech well. Don't truncate audio chunks. |
| **Mixed language (code-switching)** | Run language ID per segment. Use multilingual ASR model (Whisper) or route to appropriate model. Ensure LLM rewriter preserves code-switched segments. |
| **Dictating code or technical content** | Detect technical context (user is in IDE, or mentions code). Switch LLM prompt to preserve technical terms verbatim, handle operators and syntax. |
| **Poor network** | Buffer audio on-device. Queue for processing when connection resumes. Show "buffering" indicator. Consider a lightweight on-device ASR fallback (Whisper tiny). |
| **Accented speech** | Use ASR models trained on diverse accents (Deepgram and AssemblyAI both handle this well). Allow user to specify accent/dialect in settings. |

### 3.10 Language Switching Logic

**Implementation for a pragmatic first version**:
1. Default to user's primary language (set in onboarding).
2. Run Whisper's language detection head on the first 3 seconds of each new utterance.
3. If detected language ≠ primary language with confidence > 0.8, switch ASR to that language.
4. Maintain language state per utterance, not per word (word-level switching is extremely hard).
5. Send detected language to LLM rewriter so it applies correct punctuation/formatting rules.

### 3.11 Personalisation Memory

**Data to store per user**:
```json
{
  "style_profile": {
    "formality_by_context": {"email": 0.8, "slack": 0.3, "notes": 0.5},
    "punctuation_prefs": {"oxford_comma": false, "dash_type": "em", "ellipsis_style": "..."},
    "capitalisation_overrides": {"iphone": "iPhone", "api": "API"},
    "filler_sensitivity": "aggressive",
    "paragraph_frequency": "moderate"
  },
  "personal_dictionary": ["Kubernetes", "Figma", "Supr", "standup"],
  "correction_history": [
    {"from": "gonna", "to": "going to", "count": 7, "context": "email"},
    {"from": "gonna", "to": "gonna", "count": 12, "context": "slack"}
  ],
  "usage_stats": {
    "avg_utterance_length": 23,
    "primary_language": "en-US",
    "secondary_languages": ["hi"],
    "peak_wpm": 156
  }
}
```

### 3.12 Confidence Scoring

**Three levels of confidence to track**:
1. **ASR confidence**: Per-word confidence from the ASR model (most providers return this). Use to flag uncertain transcriptions.
2. **Rewrite confidence**: Does the LLM rewriter have high certainty about its changes? Implement by asking the LLM to flag any uncertain rewrites.
3. **Overall segment confidence**: Combined score. If below threshold, show the segment with subtle "review me" indication.

### 3.13 Fallback Mechanisms

| Failure Mode | Fallback |
|---|---|
| ASR API unavailable | On-device Whisper tiny/base model. Accuracy drops but user isn't blocked. |
| LLM API unavailable | Show ASR output with basic regex cleanup (filler removal, simple punctuation). |
| High latency (> 2s) | Skip LLM rewrite, show ASR output directly. Queue rewrite for background processing. |
| Low ASR confidence | Show transcript with visual uncertainty markers. Offer "tap to re-dictate" option. |
| Language detection failure | Fall back to user's primary language. |

---

## PART 4: RECOMMENDED TECHNICAL ARCHITECTURES

### Architecture A: Fastest to Build (2-4 weeks for core)

```
[Device Mic] → [Platform audio capture]
      ↓
[Silero VAD (on-device)]
      ↓
[Deepgram Nova-3 Streaming (WebSocket)]
      ↓
[Partial text → UI immediately]
      ↓
[On sentence commit: GPT-4o-mini rewrite call]
      ↓
[Polished text replaces rough text in UI]
```

| Aspect | Detail |
|---|---|
| **ASR** | Deepgram Nova-3 streaming via WebSocket |
| **Post-processing** | GPT-4o-mini with a well-crafted rewrite prompt |
| **VAD** | Silero VAD on-device |
| **Personalisation** | Manual personal dictionary only (no auto-learning) |
| **Languages** | English only, with Deepgram's built-in language support for future expansion |
| **Strengths** | Fast to ship, low infrastructure, good baseline quality |
| **Weaknesses** | No personalisation learning, no context-awareness by app, rewrite quality limited by prompt alone |
| **Latency** | ~400ms to partial text, ~1.2s to polished text |
| **Cost** | ~$0.005/min ASR + ~$0.001/rewrite = ~$0.006/min |
| **Complexity** | Low. One streaming connection + one API call per sentence. |

### Architecture B: Best Quality (8-16 weeks)

```
[Device Mic] → [RNNoise + AGC (on-device)]
      ↓
[Silero VAD + 3-tier endpoint detection]
      ↓
[Deepgram Nova-3 Streaming + keyword boosting from personal dictionary]
      ↓
[Partial text → UI with progressive rendering]
      ↓
[On sentence commit: Claude Haiku 4.5 rewrite with full context]
   - App context injection
   - User style profile injection
   - Rolling 5-sentence history
   - Personal dictionary
      ↓
[Polished text with smooth UI transition]
      ↓
[Edit tracking → style profile updates]
```

| Aspect | Detail |
|---|---|
| **ASR** | Deepgram Nova-3 with keyword boosting + AssemblyAI fallback |
| **Post-processing** | Claude Haiku 4.5 with rich context injection |
| **VAD** | Silero VAD with custom 3-tier endpoint logic |
| **Noise suppression** | RNNoise on-device |
| **Personalisation** | Auto-learning from corrections, style profiles, personal dictionary |
| **Context** | App-aware formatting, conversation thread awareness |
| **Languages** | English primary + top 5 languages via Whisper fallback |
| **Strengths** | Near Wispr-level quality, personalised, context-aware |
| **Weaknesses** | Higher cost, more complex infrastructure, 2-3 months to build well |
| **Latency** | ~300ms to partial text, ~900ms to polished text |
| **Cost** | ~$0.005/min ASR + ~$0.002/rewrite + infra = ~$0.01/min |
| **Complexity** | Medium-high. Requires style profile system, edit tracking, context management. |

### Architecture C: Most Cost-Efficient (4-6 weeks)

```
[Device Mic] → [Platform audio capture]
      ↓
[Silero VAD (on-device)]
      ↓
[Whisper large-v3 self-hosted on GPU (streaming via faster-whisper)]
      ↓
[Partial text → UI]
      ↓
[On sentence commit: Llama 3.1 8B self-hosted rewrite]
      ↓
[Polished text]
```

| Aspect | Detail |
|---|---|
| **ASR** | Self-hosted Whisper large-v3 via faster-whisper with streaming |
| **Post-processing** | Self-hosted Llama 3.1 8B or Mistral 7B for rewrites |
| **VAD** | Silero VAD on-device |
| **Infrastructure** | 1-2 A100/H100 GPUs (or equivalent cloud instances) |
| **Strengths** | No per-minute API costs after hardware, full control, data stays on your infra |
| **Weaknesses** | Requires ML ops expertise, GPU management, higher upfront cost, harder to iterate on models |
| **Latency** | ~500ms to partial text, ~1.5s to polished text |
| **Cost** | ~$2-4/hr GPU cost (amortised ~$0.003/min at scale, but high fixed cost at low volume) |
| **Complexity** | High. Requires GPU infrastructure, model serving, monitoring, scaling. |

**Warning**: This architecture only becomes cost-efficient above ~10,000 active users. Below that, API-based approaches (A or B) are cheaper.

### Architecture D: Ideal Premium (12-24 weeks)

```
[Device Mic] → [On-device neural preprocessor (RNNoise + AGC + echo cancel)]
      ↓
[Silero VAD + neural endpoint classifier]
      ↓
[Primary: Deepgram Nova-3 Streaming]
[Secondary: On-device Whisper base for offline / fallback]
      ↓
[Partial text → UI with word-level confidence highlighting]
      ↓
[Context assembly engine]:
   - Current app / text field detection
   - Conversation thread (if replying)
   - User style profile
   - Personal + domain dictionary
   - Rolling context window (last 10 sentences)
   - Detected language + formality level
      ↓
[Claude Sonnet 4.6 rewrite for complex segments]
[Claude Haiku 4.5 rewrite for simple segments (cost optimisation)]
      ↓
[Polished text with animated transition]
      ↓
[Correction engine]:
   - Edit tracking with Myers diff
   - Pattern extraction + clustering
   - Style profile auto-update
   - A/B testing of profile variations
      ↓
[Speaker model]:
   - Voice fingerprint for speaker verification
   - Personal acoustic model adaptation
   - Accent-aware ASR routing
```

| Aspect | Detail |
|---|---|
| **Strengths** | Closest possible match to Wispr Flow. Personalised, context-aware, fast, reliable, works offline. |
| **Weaknesses** | 6+ months to build. Requires dedicated ML engineer. High ongoing cost. |
| **Latency** | ~200ms to partial text, ~700ms to polished text |
| **Cost** | ~$0.015/min all-in |
| **Complexity** | Very high. Multiple models, on-device + cloud hybrid, personalisation engine, speaker model. |

---

## PART 5: GAP ANALYSIS — Typical App vs Wispr Flow-Like Implementation

| Dimension | What Most Apps Do | What Wispr Flow Does | What You Must Add |
|---|---|---|---|
| **ASR approach** | Batch (record → send → wait) | Streaming with partial hypotheses | Switch to streaming ASR with persistent WebSocket |
| **First visible text** | 2-5 seconds after speaking | < 300ms after speaking | Streaming partials to UI immediately |
| **Punctuation** | None, or basic ASR-provided | Multi-pass: ASR punctuation + LLM restoration | Add LLM rewrite pass with punctuation focus |
| **Capitalisation** | Sentence-initial only | Context-aware (proper nouns, acronyms, brand names) | Personal dictionary + LLM capitalisation |
| **Filler words** | Transcribed verbatim ("um, so, like...") | Completely removed | Filler removal in post-processing (regex + LLM) |
| **Self-corrections** | Transcribed verbatim ("Tuesday, no, Wednesday") | Resolved to intent ("Wednesday") | Self-correction resolution in LLM rewrite prompt |
| **Context awareness** | None — same output regardless of where text goes | Adjusts tone/formality per app (email vs chat) | App context detection + context-conditioned LLM prompt |
| **Personalisation** | None | Learns from corrections, adapts to user style | Edit tracking + style profile + injection into prompts |
| **Custom vocabulary** | None or manual-only | Personal dictionary with auto-learning | Dictionary management + ASR keyword boosting |
| **Formatting** | Raw paragraph of text | Properly structured: paragraphs, lists, appropriate formatting | Paragraph detection + LLM formatting |
| **Error recovery** | Show error, lose transcript | On-device fallback, audio buffering, retry | Offline fallback model + audio buffer + retry logic |
| **Number handling** | "twenty three dollars" stays as text | Converts to "$23" contextually | Number formatting rules in post-processing |
| **UI feedback** | Loading spinner while processing | Progressive text reveal, smooth transitions | Streaming UI with partial → final transitions |
| **Multilingual** | Single language or manual switch | Auto-detection and switching | Language ID model + multilingual ASR routing |
| **Commands** | None | "make this more professional," "delete that" | Intent classifier + command execution engine |
| **Noise handling** | Whatever the mic captures | Active noise suppression, gain normalisation | On-device audio preprocessing pipeline |
| **Endpoint detection** | Simple silence timeout | Multi-tier (comma vs period vs paragraph) | Custom endpoint logic on top of VAD |

**The blunt summary**: A typical app ships raw ASR output to the user. Wispr Flow ships *editorially polished text that matches the user's personal writing style*. The gap is approximately 15 distinct engineering features on top of the base ASR.

---

## PART 6: PRIORITISED ACTION PLAN

### Phase 1: Biggest Wins, Least Complexity (Weeks 1-4)

These changes will make your app feel dramatically better with relatively low engineering effort.

| # | Feature | Why It Matters | Difficulty | Affects |
|---|---|---|---|---|
| 1 | **Switch to streaming ASR (Deepgram Nova-3)** | Eliminates the "wait for transcript" gap entirely. Text appears as user speaks. | Medium | Speed |
| 2 | **Add LLM rewrite pass (GPT-4o-mini / Haiku)** | Single biggest quality improvement. Handles punctuation, filler removal, self-correction, formatting in one call. | Low | Accuracy, Intelligence |
| 3 | **Implement Silero VAD on-device** | Proper speech detection, cleaner audio sent to ASR, better endpoint detection. | Low | Speed, Accuracy |
| 4 | **Progressive UI rendering** | Show partial ASR text immediately, replace with polished text on commit. Creates the "typing as I speak" feel. | Medium | Speed (perceived) |
| 5 | **Basic personal dictionary** | Let users add custom words. Inject as ASR keywords. Fixes the most annoying recurring errors. | Low | Accuracy |

**Dependencies**: #1 must come first. #2 and #3 can be parallel. #4 depends on #1. #5 is independent.

**Expected impact**: These five changes alone will close roughly 60% of the gap to Wispr Flow.

### Phase 2: Major Quality Upgrades (Weeks 5-10)

| # | Feature | Why It Matters | Difficulty | Affects |
|---|---|---|---|---|
| 6 | **Three-tier endpoint detection** | Distinguishes commas, periods, and paragraphs. Makes long dictation structured instead of a wall of text. | Medium | Intelligence |
| 7 | **Context-conditioned rewriting** | Adjust tone/formality based on where the text is going (email, notes, chat). | Medium | Intelligence |
| 8 | **Edit tracking + basic style learning** | Start capturing user corrections. Build simple style profile (punctuation prefs, formality). | Medium | Intelligence |
| 9 | **On-device noise suppression** | RNNoise integration. Better audio = better ASR accuracy, especially in noisy environments. | Low-Medium | Accuracy |
| 10 | **Number and date formatting** | Convert spoken numbers, dates, currency to proper written format. | Low | Accuracy |
| 11 | **Filler word classifier** | Distinguish filler "like" from meaningful "like." Prevents over-aggressive removal. | Medium | Accuracy |

**Dependencies**: #7 requires app context detection (platform-specific). #8 requires a diff engine and storage. Others are independent.

**Expected impact**: Closes another 20% of the gap. Your app now feels "smart."

### Phase 3: Advanced Intelligence and Polish (Weeks 11-18)

| # | Feature | Why It Matters | Difficulty | Affects |
|---|---|---|---|---|
| 12 | **Full personalisation engine** | Auto-learning from corrections, style profile per context, preference injection. | High | Intelligence |
| 13 | **Multilingual detection and switching** | Handle code-switching, auto-detect language changes. | High | Accuracy |
| 14 | **Spoken command parsing** | "Delete that," "new paragraph," "make this more professional." | Medium-High | Intelligence |
| 15 | **On-device ASR fallback** | Whisper tiny/base on-device for offline and poor-network scenarios. | Medium | Reliability |
| 16 | **Confidence scoring and uncertainty UI** | Show users when the system is less sure. Let them tap to correct. | Medium | Accuracy, Trust |
| 17 | **Speaker verification** | Only transcribe the primary user's voice, ignore background speech. | High | Accuracy |

**Dependencies**: #12 depends on #8. #14 requires intent classifier training. #15 requires on-device model integration.

### Phase 4: Premium Moat Features (Weeks 19-30+)

| # | Feature | Why It Matters | Difficulty | Affects |
|---|---|---|---|---|
| 18 | **Acoustic model personalisation** | Adapt the ASR to the user's specific voice, accent, speech patterns. | Very High | Accuracy |
| 19 | **Cross-device sync of personalisation** | Style profiles, dictionary, preferences sync across phone/tablet/desktop. | Medium | Intelligence |
| 20 | **Real-time rewrite preview** | Show the user how their text will look *before* committing (useful for emails). | Medium | Intelligence, Trust |
| 21 | **Domain-specific modes** | Medical, legal, technical, creative writing — each with specialised vocabulary and formatting rules. | High | Accuracy |
| 22 | **Conversation-aware replies** | When replying to a message, consider the message thread for context. | High | Intelligence |
| 23 | **A/B testing framework for rewrite quality** | Systematically test prompt variations, model versions, and profile strategies. | Medium | All |

---

## PART 7: HARD TRUTHS

### What's Realistic for a Small Team (1-3 engineers)

**Absolutely achievable**:
- Streaming ASR integration (Deepgram/AssemblyAI) — this is just an API
- LLM post-processing pass — this is just an API call with a good prompt
- VAD integration — Silero is open-source and tiny
- Personal dictionary with keyword boosting
- Progressive UI rendering
- Basic filler removal and formatting
- Three-tier endpoint detection

**Achievable with effort**:
- Edit tracking and basic style learning
- Context-conditioned rewriting (requires app context detection, which is platform-specific work)
- Number/date formatting
- On-device noise suppression
- Spoken command parsing (basic set)

### What's Genuinely Difficult

- **Full personalisation engine with RL-style learning**: Wispr has ML researchers working specifically on this. A rule-based approximation gets you 70% of the value, but the last 30% requires real ML engineering.
- **Multilingual with seamless switching**: Getting 100+ languages working well requires either a large multilingual model (with per-language accuracy tradeoffs) or routing logic to dozens of language-specific models. Wispr likely uses a combination.
- **Acoustic model adaptation**: Fine-tuning ASR models per user requires infrastructure for model training, versioning, and serving that is far beyond a small team.
- **On-device ASR that's actually good**: Whisper tiny on a phone is usable but significantly worse than cloud ASR. Whisper base is better but uses 200MB+ RAM and drains battery.

### What's Mostly Product/UX Magic vs Model Quality

This is critical to understand: **at least 40% of Wispr's perceived quality comes from UX, not models**.

- **Progressive text rendering** makes the app feel faster than it is
- **Smooth transitions** from rough to polished text hide the processing time
- **No loading states** create the perception of instant intelligence
- **The "it just works in every app" behavior** is a platform engineering achievement, not an ML one
- **The personal dictionary** is a simple feature but creates disproportionate user satisfaction
- **Confidence in the output** (proper punctuation, clean formatting) creates trust, which creates the perception of accuracy even when individual words are occasionally wrong

**Implication for you**: Invest heavily in UX polish. A mediocre model with excellent UX will *feel* better than an excellent model with mediocre UX.

### What Requires Proprietary Data, Infra, or Long-Term Tuning

- **Style learning from millions of users**: Wispr has aggregate data on how people correct transcriptions. This informs their default rewrite behavior. You won't have this on day one.
- **Context-conditioned ASR models**: Wispr is building custom ASR models that take context as input. This requires training data, compute, and ML expertise that is impractical for a small team. The workaround (context-conditioned LLM rewriting) gets you 80% of the way.
- **Per-language accuracy optimisation**: Each language requires evaluation data, tuning, and testing. Wispr's 100+ language claim likely means "Whisper handles these" with varying quality.

### What's Likely Impossible Without Major Investment

- **Exact parity with Wispr's personalisation**: They've spent years and raised significant funding to build their correction learning system. You can approximate it, not replicate it.
- **Sub-200ms end-to-end polished text**: Getting polished (LLM-rewritten) text in < 200ms requires either on-device LLM inference (feasible on high-end devices with small models, but quality drops) or geographically distributed GPU inference (expensive).
- **Working perfectly in 100+ languages**: Realistic for 5-10 languages. Diminishing returns after that for most apps.
- **Custom ASR model training**: Requires millions of hours of labelled audio data and significant compute budget.

---

## PART 8: FINAL RECOMMENDATIONS

### Minimum Viable Stack to Get Meaningfully Closer to Wispr Flow

```
┌──────────────────────────────────────────────┐
│              ON DEVICE                        │
│  ┌─────────┐  ┌───────────┐  ┌────────────┐ │
│  │ Audio   │→ │ Silero    │→ │ Audio      │ │
│  │ Capture │  │ VAD       │  │ Chunker    │ │
│  └─────────┘  └───────────┘  └────────────┘ │
│                                     │        │
└─────────────────────────────────────┼────────┘
                                      │ WebSocket
┌─────────────────────────────────────┼────────┐
│              CLOUD                  ↓        │
│  ┌──────────────────────────────────────┐    │
│  │ Deepgram Nova-3 Streaming ASR        │    │
│  │ + keyword boosting from dictionary   │    │
│  └──────────────────┬───────────────────┘    │
│                     ↓                        │
│  ┌──────────────────────────────────────┐    │
│  │ GPT-4o-mini / Claude Haiku 4.5      │    │
│  │ Rewrite with:                        │    │
│  │  - Filler removal                    │    │
│  │  - Punctuation restoration           │    │
│  │  - Self-correction resolution        │    │
│  │  - Basic formatting                  │    │
│  └──────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
```

**Time to build**: 3-4 weeks.
**Cost per user**: ~$0.006/min of dictation. At 30 min/day = ~$5.40/month.
**Quality**: Closes ~60% of the gap to Wispr Flow.

### Ideal Stack if Quality Is Top Priority

```
┌──────────────────────────────────────────────────────┐
│                    ON DEVICE                          │
│  ┌─────────┐ ┌────────┐ ┌───────────┐ ┌──────────┐ │
│  │ Audio   │→│RNNoise │→│ Silero    │→│ 3-tier   │ │
│  │ Engine  │ │+ AGC   │ │ VAD       │ │ Endpoint │ │
│  └─────────┘ └────────┘ └───────────┘ └──────────┘ │
│                                           │          │
│  ┌────────────────────────────────────────┤          │
│  │ Whisper base (offline fallback)        │          │
│  └────────────────────────────────────────┘          │
│  ┌────────────────────────────────────────┐          │
│  │ Edit tracker + Style profile store     │          │
│  └────────────────────────────────────────┘          │
│  ┌────────────────────────────────────────┐          │
│  │ Personal dictionary + language ID      │          │
│  └────────────────────────────────────────┘          │
└──────────────────────────────────────────┼───────────┘
                                           │
┌──────────────────────────────────────────┼───────────┐
│                    CLOUD                 ↓           │
│  ┌──────────────────────────────────────────────┐    │
│  │ Deepgram Nova-3 Streaming ASR                │    │
│  │ + keyword boosting + language routing         │    │
│  │ + AssemblyAI fallback                         │    │
│  └─────────────────────┬────────────────────────┘    │
│                        ↓                             │
│  ┌──────────────────────────────────────────────┐    │
│  │ Context Assembly Engine                       │    │
│  │  - App context (email/chat/notes)             │    │
│  │  - Conversation thread (if replying)          │    │
│  │  - User style profile                         │    │
│  │  - Personal dictionary                        │    │
│  │  - Rolling 10-sentence history                │    │
│  │  - Detected language + formality              │    │
│  └─────────────────────┬────────────────────────┘    │
│                        ↓                             │
│  ┌──────────────────────────────────────────────┐    │
│  │ Claude Haiku 4.5 (simple) / Sonnet (complex) │    │
│  │ Context-conditioned rewrite                   │    │
│  └─────────────────────┬────────────────────────┘    │
│                        ↓                             │
│  ┌──────────────────────────────────────────────┐    │
│  │ Spoken command interpreter                    │    │
│  │ Intent classifier + command executor          │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Personalisation service                       │    │
│  │  - Edit pattern analysis                      │    │
│  │  - Style profile sync                         │    │
│  │  - A/B test framework for rewrite quality     │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

**Time to build**: 4-6 months with 2-3 engineers.
**Cost per user**: ~$0.015/min. At 30 min/day = ~$13.50/month.
**Quality**: Closes ~85-90% of the gap to Wispr Flow.

### The 10 Highest-Leverage Improvements (In Order)

| Rank | Improvement | Impact | Effort | ROI |
|---|---|---|---|---|
| **1** | Switch to streaming ASR (Deepgram Nova-3) | Eliminates perceived latency entirely. Transforms the core experience. | 1 week | Extreme |
| **2** | Add LLM rewrite pass on sentence commit | Fixes punctuation, removes fillers, resolves self-corrections, formats text. One feature that addresses 5 problems. | 3-5 days | Extreme |
| **3** | Progressive UI rendering (partial → polished) | Makes the app feel 3-5x faster than it technically is. Pure UX magic. | 1 week | Extreme |
| **4** | Silero VAD with proper endpoint detection | Better speech boundaries = better ASR accuracy + better sentence segmentation + proper punctuation | 3 days | Very High |
| **5** | Personal dictionary with ASR keyword boosting | Fixes the user's most annoying recurring errors. Disproportionate satisfaction impact. | 2-3 days | Very High |
| **6** | Craft and iterate the rewrite prompt extensively | The prompt is the product. Spend 2+ weeks testing edge cases, refining rules, handling corner cases. Each prompt improvement is free at runtime. | 2 weeks | Very High |
| **7** | Three-tier endpoint detection (clause/sentence/paragraph) | Transforms long dictation from "wall of text" to "structured content." Critical for your mental-load user base. | 1 week | High |
| **8** | Edit tracking + basic style profile | Start capturing corrections. Even before auto-learning, this data is invaluable for understanding user needs. | 1-2 weeks | High |
| **9** | On-device noise suppression (RNNoise) | Improves accuracy in real-world conditions (cafés, commutes, open offices). Your users won't dictate in quiet rooms. | 3-5 days | High |
| **10** | Smooth text transition animations | When rough text becomes polished text, animate the change. Prevents the jarring "text just changed" feeling. Completes the "magic" perception. | 3-5 days | High |

**Total time for all 10**: Approximately 8-10 weeks for one engineer. These 10 improvements alone will make your app feel like a completely different product.

---

## Appendix: Key Vendor/Tool Reference

| Component | Recommended Tool | Alternative | Notes |
|---|---|---|---|
| Streaming ASR | Deepgram Nova-3 | AssemblyAI Streaming, Google Cloud STT v2 | Deepgram has best latency-to-cost ratio |
| LLM Rewriting | Claude Haiku 4.5 | GPT-4o-mini, Gemini 2.0 Flash | All viable; test all three and pick based on output quality for your prompt |
| On-device VAD | Silero VAD | WebRTC VAD | Silero is more accurate, WebRTC is simpler |
| Noise Suppression | RNNoise | Apple Neural Engine (iOS only), Krisp SDK | RNNoise is open-source and cross-platform |
| On-device ASR fallback | Whisper base (via whisper.cpp) | Whisper tiny (faster, less accurate) | Only for offline fallback, not primary path |
| Language ID | Whisper language detection | Meta MMS-LID | Whisper's is free if you're already loading Whisper for fallback |
| Diff Engine | Myers diff (any implementation) | — | For edit tracking |
| Personal Dictionary Storage | SQLite (on-device) + cloud sync | Realm, Core Data | Keep it simple |

---

*This document is a technical reference for implementation planning. Model capabilities, API pricing, and vendor features are current as of April 2026 and should be verified before purchasing decisions.*
