import XCTest
@testable import Gotm

// MARK: - Test Utilities

/// Utilities for testing the dictation rewrite system
enum RewriteTestUtilities {
    
    // MARK: - Sample Transcripts
    
    static let sampleTranscripts: [(input: String, expectedCharacteristics: [String])] = [
        (
            input: "um so I was thinking we should probably you know meet on tuesday no wait wednesday",
            expectedCharacteristics: ["filler_removed", "correction_resolved", "capitalized"]
        ),
        (
            input: "can you send me the the report",
            expectedCharacteristics: ["repetition_removed"]
        ),
        (
            input: "three pm to discuss the project",
            expectedCharacteristics: ["time_formatted", "capitalized"]
        ),
        (
            input: "twenty three dollars for the meal",
            expectedCharacteristics: ["currency_formatted"]
        ),
    ]
    
    // MARK: - Context Builders
    
    static func notesContext() -> RewriteContext {
        RewriteContext(
            appType: .notes,
            styleProfile: StyleProfile.default,
            locale: "en-US",
            detectedLanguage: "en"
        )
    }
    
    static func emailContext() -> RewriteContext {
        RewriteContext(
            appType: .email,
            recipientContext: "Professional correspondence",
            styleProfile: StyleProfile(
                oxfordComma: true,
                dashStyle: .em,
                contractionPreference: .never,
                formalityOverrides: [:],
                capitalisationOverrides: [:],
                paragraphFrequency: .moderate,
                listStyle: .inline,
                sentenceLengthPreference: .mixed,
                ellipsisStyle: .ellipsis,
                quotationStyle: .double,
                timeFormat: .twelveHour,
                dateFormat: .us
            ),
            personalDictionaryTerms: [],
            locale: "en-US",
            detectedLanguage: "en"
        )
    }
    
    static func chatContext() -> RewriteContext {
        RewriteContext(
            appType: .chat,
            recipientContext: "Casual conversation",
            styleProfile: StyleProfile(
                oxfordComma: false,
                dashStyle: .em,
                contractionPreference: .always,
                formalityOverrides: [:],
                capitalisationOverrides: [:],
                paragraphFrequency: .sparse,
                listStyle: .inline,
                sentenceLengthPreference: .short,
                ellipsisStyle: .dots,
                quotationStyle: .double,
                timeFormat: .twelveHour,
                dateFormat: .us
            ),
            personalDictionaryTerms: [],
            locale: "en-US",
            detectedLanguage: "en"
        )
    }
    
    // MARK: - Assertion Helpers
    
    /// Asserts that a transcript is considered valid
    static func assertValidTranscript(_ transcript: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            ComposeViewModel.isValidTranscriptStatic(transcript),
            "Expected '\(transcript)' to be valid",
            file: file,
            line: line
        )
    }
    
    /// Asserts that a transcript is considered invalid
    static func assertInvalidTranscript(_ transcript: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(
            ComposeViewModel.isValidTranscriptStatic(transcript),
            "Expected '\(transcript)' to be invalid",
            file: file,
            line: line
        )
    }
    
    /// Asserts that a response is considered garbage
    static func assertGarbageResponse(_ response: String, comparedTo original: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            TranscriptionService.isGarbageResponse(response, comparedTo: original),
            "Expected '\(response)' to be garbage",
            file: file,
            line: line
        )
    }
    
    /// Asserts that a response is NOT considered garbage
    static func assertValidResponse(_ response: String, comparedTo original: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(
            TranscriptionService.isGarbageResponse(response, comparedTo: original),
            "Expected '\(response)' to be valid",
            file: file,
            line: line
        )
    }
}

// MARK: - Mock Services

/// Mock TranscriptionService for testing without actual transcription
class MockTranscriptionService {
    
    var mockTranscript: String?
    var shouldFail = false
    
    func transcribe(fileURL: URL) async throws -> String {
        if shouldFail {
            throw TranscriptionError.deepgramFailed
        }
        return mockTranscript ?? "Mock transcript"
    }
    
    func formatWithAI(_ transcript: String, context: RewriteContext) async -> String {
        // Simple mock formatting
        return transcript
            .replacingOccurrences(of: " um ", with: " ")
            .replacingOccurrences(of: " uh ", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Mock PersonalDictionary for isolated testing
@MainActor
class MockPersonalDictionary {
    
    private var entries: [DictionaryEntry] = []
    
    func add(_ term: String, category: TermCategory = .general) {
        let entry = DictionaryEntry(term: term, category: category)
        entries.append(entry)
    }
    
    func contains(_ term: String) -> Bool {
        entries.contains { $0.normalizedTerm == term.lowercased() }
    }
    
    var allTerms: [String] {
        entries.map { $0.term }
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {
    
    /// Creates a temporary directory for test files
    func createTemporaryDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    /// Cleans up a temporary directory
    func cleanupTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Measures the execution time of a block
    func measureExecutionTime(_ name: String, block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        let duration = Date().timeIntervalSince(start)
        print("[Performance] \(name): \(String(format: "%.4f", duration))s")
        return duration
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {
    
    /// Runs an async test with a timeout
    func runAsyncTest(timeout: TimeInterval = 5.0, test: @escaping () async throws -> Void) async {
        let expectation = self.expectation(description: "Async test completion")
        
        Task {
            do {
                try await test()
                expectation.fulfill()
            } catch {
                XCTFail("Test failed with error: \(error)")
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
}
