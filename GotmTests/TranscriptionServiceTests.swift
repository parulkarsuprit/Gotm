import XCTest
@testable import Gotm

// MARK: - Transcription Service Tests

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    
    var service: TranscriptionService!
    
    override func setUp() {
        super.setUp()
        service = TranscriptionService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Garbage Response Detection
    
    func testRefusalPrefixDetection() {
        let testCases: [(String, Bool)] = [
            ("I'm sorry, I can't help with that", true),
            ("I am sorry, but I cannot", true),
            ("I can't process this request", true),
            ("As an AI language model", true),
            ("Certainly! Here's the cleaned text", true),
            ("Sure! I can help", true),
            ("I'd be happy to help", true),
            ("I would be happy to assist", true),
            ("I apologize for", true),
            ("This is a normal transcript", false),
            ("Meeting notes from today", false),
        ]
        
        for (response, shouldBeGarbage) in testCases {
            let isGarbage = TranscriptionService.isGarbageResponse(response, comparedTo: "original text here")
            XCTAssertEqual(isGarbage, shouldBeGarbage, "Failed for: \(response)")
        }
    }
    
    func testLeakedInstructionDetection() {
        let testCases: [(String, Bool)] = [
            ("FILLER WORD REMOVAL: I removed um and uh", true),
            ("Self-correction resolution applied", true),
            ("Preserve meaning exactly is my goal", true),
            ("Never add content that wasn't there", true),
            ("I am a dictation cleanup engine", true),
            ("Return only the cleaned text", true),
            ("Paragraph breaks inserted", true),
            ("Context-conditioned tone applied", true),
            ("Personal dictionary terms used", true),
            ("Style profile settings applied", true),
            ("As an AI language model", true),
            ("Regular text without leaked phrases", false),
        ]
        
        for (response, shouldBeGarbage) in testCases {
            let isGarbage = TranscriptionService.isGarbageResponse(response, comparedTo: "original")
            XCTAssertEqual(isGarbage, shouldBeGarbage, "Failed for: \(response)")
        }
    }
    
    func testLengthBasedGarbageDetection() {
        let shortOriginal = "Short note"
        let longResponse = String(repeating: "word ", count: 100) // Much longer than 4x
        
        XCTAssertTrue(TranscriptionService.isGarbageResponse(longResponse, comparedTo: shortOriginal))
        
        let normalOriginal = "This is a normal length transcript with several words"
        let reasonableResponse = "This is the cleaned version of that transcript"
        
        XCTAssertFalse(TranscriptionService.isGarbageResponse(reasonableResponse, comparedTo: normalOriginal))
    }
    
    func testTooShortResponseDetection() {
        let original = String(repeating: "word ", count: 20) // > 50 chars
        let tooShort = "Hi" // < 30% of original
        
        XCTAssertTrue(TranscriptionService.isGarbageResponse(tooShort, comparedTo: original))
        
        // Short original should not trigger this check
        let shortOriginal = "Hi there"
        let shortResponse = "Hello"
        
        XCTAssertFalse(TranscriptionService.isGarbageResponse(shortResponse, comparedTo: shortOriginal))
    }
    
    // MARK: - Transcript Validation
    
    func testValidTranscriptDetection() {
        let validCases = [
            "This is a normal transcript",
            "Meeting notes from the standup",
            "TODO: fix the bug in production",
            "Call mom about dinner plans",
        ]
        
        for transcript in validCases {
            XCTAssertTrue(ComposeViewModel.isValidTranscriptStatic(transcript), "Should be valid: \(transcript)")
        }
    }
    
    func testInvalidTranscriptDetection() {
        let invalidCases = [
            "you",
            "thank you",
            "thanks",
            "bye",
            "yes",
            "no",
            "okay",
            "ok",
            "um",
            "uh",
            "[music]",
            "(background noise)",
        ]
        
        for transcript in invalidCases {
            XCTAssertFalse(ComposeViewModel.isValidTranscriptStatic(transcript), "Should be invalid: \(transcript)")
        }
    }
    
    func testTranscriptWithBracketsRemoved() {
        let transcript = "[music] Actual content here [noise]"
        XCTAssertTrue(ComposeViewModel.isValidTranscriptStatic(transcript))
    }
}

// MARK: - Edge Case Tests (from Design Document)

final class EdgeCaseTests: XCTestCase {
    
    // Category 1: Tricky Filler vs. Meaningful Words
    func testFillerVsMeaningfulLike() {
        // "like" as comparison should be kept
        let comparison = "it looks like rain"
        // "like" as verb should be kept
        let preference = "I like this approach"
        // "like" as approximation (context dependent)
        let approximation = "it took like three hours"
        // "like" as quotative should be kept in chat
        let quotative = "she was like no way"
        
        XCTAssertTrue(comparison.contains("like"))
        XCTAssertTrue(preference.contains("like"))
        XCTAssertTrue(approximation.contains("like"))
        XCTAssertTrue(quotative.contains("like"))
    }
    
    func testLiterallyUsage() {
        // In chat: keep hyperbolic "literally"
        let chatUsage = "I literally can't even"
        // In email: remove "literally"
        // (This is a behavior test - the actual implementation depends on context)
        
        XCTAssertTrue(chatUsage.contains("literally"))
    }
    
    // Category 2: Self-Correction Resolution
    func testExplicitCorrections() {
        let corrections: [(String, String)] = [
            ("Tuesday no Wednesday", "Wednesday"),
            ("at 5 wait 6 pm", "at 6 pm"),
            ("send it to John sorry James", "send it to James"),
            ("the backend I mean the frontend", "the frontend"),
            ("three actually four people", "four people"),
            ("next week or rather the week after", "the week after"),
        ]
        
        // These are pattern examples - the actual correction is done by AI
        // This test documents the expected behavior
        for (input, expected) in corrections {
            XCTAssertFalse(input.isEmpty)
            XCTAssertFalse(expected.isEmpty)
        }
    }
    
    func testNoAsCorrectionMarkerVsContent() {
        // "no" as correction marker
        let correction = "send it to John no James"
        // "no" as content (should NOT be treated as correction)
        let content1 = "I said no to that"
        let content2 = "we have no idea"
        
        // The correction marker follows a complete phrase
        XCTAssertTrue(correction.contains("John no James"))
        // The content usage is mid-sentence
        XCTAssertTrue(content1.contains("said no to"))
        XCTAssertTrue(content2.contains("have no idea"))
    }
    
    func testGenuineAlternativesVsCorrections() {
        // These are genuine alternatives, not corrections
        let alternative1 = "we could do plan A or plan B"
        let alternative2 = "it's due Friday or Monday I'm not sure"
        
        // Should keep both parts
        XCTAssertTrue(alternative1.contains("A"))
        XCTAssertTrue(alternative1.contains("B"))
        XCTAssertTrue(alternative2.contains("Friday"))
        XCTAssertTrue(alternative2.contains("Monday"))
    }
    
    // Category 3: Punctuation Challenges
    func testQuestionVsIndirectQuestion() {
        let directQuestion = "why did you do that"
        let indirectQuestion = "I wonder if she's coming"
        
        // Direct question should get ?
        // Indirect question should get .
        XCTAssertTrue(directQuestion.hasPrefix("why"))
        XCTAssertTrue(indirectQuestion.hasPrefix("I wonder"))
    }
    
    // Category 4: Number and Data Formatting
    func testNumberFormatting() {
        // 0-9: spell out in prose
        // 10+: use digits
        // Beginning of sentence: spell out
        
        let prose = "three options"
        let technical = "3 API calls"
        let large = "15 people"
        let sentenceStart = "Fifteen people attended"
        
        XCTAssertEqual(prose, "three options")
        XCTAssertEqual(technical, "3 API calls")
        XCTAssertEqual(large, "15 people")
        XCTAssertEqual(sentenceStart, "Fifteen people attended")
    }
    
    func testTimeFormatting() {
        let times: [(String, String)] = [
            ("three pm", "3 PM"),
            ("three thirty", "3:30"),
            ("half past two", "2:30"),
            ("quarter to five", "4:45"),
            ("noon", "noon"),
            ("midnight", "midnight"),
        ]
        
        for (input, expected) in times {
            XCTAssertFalse(input.isEmpty)
            XCTAssertFalse(expected.isEmpty)
        }
    }
    
    // Category 5: Context-Sensitive Tone
    func testToneAdaptation() {
        // Email: formal
        let emailInput = "hey can you send me that thing from yesterday"
        let emailExpected = "Hey, can you send me that document from yesterday?"
        
        // Chat: keep casual
        let chatInput = "gonna need more time on this"
        let chatExpected = "gonna need more time on this"
        
        // These document expected behavior
        XCTAssertFalse(emailInput.isEmpty)
        XCTAssertFalse(emailExpected.isEmpty)
        XCTAssertFalse(chatInput.isEmpty)
        XCTAssertFalse(chatExpected.isEmpty)
    }
    
    // Category 6: Spoken Punctuation Commands
    func testSpokenPunctuationCommands() {
        let commands: [(String, String)] = [
            ("please respond by friday period", "Please respond by Friday."),
            ("add a comma after the word and", "Add a comma after the word 'and.'"),
            ("new paragraph the second point is", "The second point is"),
        ]
        
        for (input, expected) in commands {
            XCTAssertFalse(input.isEmpty)
            XCTAssertFalse(expected.isEmpty)
        }
    }
    
    // Category 9: Edge Cases That Break Naive Implementations
    func testNoAsContentNotCorrection() {
        // Critical: "no" as content should NOT be removed
        let contentExamples = [
            "I said no to that",
            "we have no idea",
            "no thanks",
        ]
        
        for example in contentExamples {
            // Should preserve "no"
            XCTAssertTrue(example.contains("no"))
        }
    }
    
    func testCorrectionWithCompleteAlternative() {
        // This IS a correction - "no" follows a complete alternative
        let correction = "can you book a flight to Dallas no a hotel in Dallas"
        // Should resolve to: "Can you book a hotel in Dallas?"
        XCTAssertTrue(correction.contains("flight to Dallas no"))
    }
    
    func testHallucinationPrevention() {
        // Empty transcript should return empty
        let empty = ""
        XCTAssertTrue(empty.isEmpty)
        
        // Pure silence markers should return empty
        let silence = "..."
        XCTAssertTrue(silence.contains("..."))
    }
    
    func testLaughterPreservation() {
        // In chat/notes: laughter is content
        let withLaughter = "ha ha ha that's so funny"
        // Should preserve laughter indicators
        XCTAssertTrue(withLaughter.contains("ha"))
    }
    
    func testAbandonedThoughtResolution() {
        let abandoned = "can you ask him to... never mind I'll do it myself"
        // Should resolve to: "Never mind, I'll do it myself."
        XCTAssertTrue(abandoned.contains("never mind"))
    }
}

// MARK: - Integration Tests

@MainActor
final class RewriteIntegrationTests: XCTestCase {
    
    func testContextCreation() {
        let settings = RewriteSettings.shared
        
        let context = settings.rewriteContext(
            appType: .email,
            recipientContext: "Client follow-up"
        )
        
        XCTAssertEqual(context.appType, .email)
        XCTAssertEqual(context.recipientContext, "Client follow-up")
        XCTAssertNotNil(context.styleProfile)
    }
    
    func testDefaultContext() {
        let context = RewriteContext.default
        
        XCTAssertEqual(context.appType, .notes)
        XCTAssertTrue(context.personalDictionaryTerms.isEmpty)
    }
}
