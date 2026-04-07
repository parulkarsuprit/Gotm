import XCTest
@testable import Gotm

// MARK: - Performance Tests

@MainActor
final class RewritePerformanceTests: XCTestCase {
    
    // MARK: - Personal Dictionary Performance
    
    func testDictionaryLookupPerformance() {
        let dictionary = PersonalDictionary.shared
        
        // Add many terms
        let terms = (1...1000).map { "Term\($0)" }
        dictionary.addTerms(terms, category: .general)
        
        measure {
            for _ in 0..<100 {
                _ = dictionary.contains("Term500")
                _ = dictionary.contains("nonexistent")
            }
        }
    }
    
    func testRelevantTermsScoringPerformance() {
        let dictionary = PersonalDictionary.shared
        
        // Add many terms
        let terms = (1...500).map { "TechnicalTerm\($0)" }
        dictionary.addTerms(terms, category: .technical)
        
        let longTranscript = String(repeating: "TechnicalTerm1 TechnicalTerm2 TechnicalTerm3 ", count: 100)
        
        measure {
            for _ in 0..<50 {
                _ = dictionary.relevantTerms(for: longTranscript, limit: 20)
            }
        }
    }
    
    // MARK: - JSON Encoding Performance
    
    func testRewriteRequestEncodingPerformance() {
        let profile = StyleProfile.default
        let context = RewriteContext(
            appType: .email,
            recipientContext: "Reply to the engineering team about the Q2 planning meeting and roadmap discussion",
            precedingText: "Let's discuss the roadmap for next quarter.",
            styleProfile: profile,
            personalDictionaryTerms: (1...100).map { "Term\($0)" },
            locale: "en-US",
            detectedLanguage: "en"
        )
        
        let endpointMetadata = EndpointMetadata(
            pauseType: .sentenceEnd,
            segmentDurationMs: 5000,
            isContinuation: false,
            confidence: 0.95
        )
        
        let request = RewriteRequest(
            rawTranscript: String(repeating: "This is a test transcript with many words ", count: 50),
            context: context,
            endpointMetadata: endpointMetadata
        )
        
        let encoder = JSONEncoder()
        
        measure {
            for _ in 0..<100 {
                _ = try? encoder.encode(request)
            }
        }
    }
}

// MARK: - Stress Tests

final class RewriteStressTests: XCTestCase {
    
    func testLargePersonalDictionary() {
        let dictionary = PersonalDictionary.shared
        
        // Add 10,000 terms
        let terms = (1...10000).map { "BulkTerm\($0)" }
        
        let start = Date()
        dictionary.addTerms(terms, category: .general)
        let duration = Date().timeIntervalSince(start)
        
        // Should complete in reasonable time
        XCTAssertLessThan(duration, 5.0)
        
        // Verify lookup still works
        XCTAssertTrue(dictionary.contains("BulkTerm5000"))
    }
    
    func testRepeatedAddOperations() {
        let dictionary = PersonalDictionary.shared
        
        // Add the same term many times
        let start = Date()
        for i in 0..<1000 {
            dictionary.add("RepeatedTerm\(i % 10)", category: .general)
        }
        let duration = Date().timeIntervalSince(start)
        
        // Should be fast due to early exit on existing terms
        XCTAssertLessThan(duration, 2.0)
    }
    
    func testVeryLongTranscriptRelevance() {
        let dictionary = PersonalDictionary.shared
        dictionary.addTerms(["Swift", "SwiftUI", "UIKit"], category: .technical)
        
        let veryLongTranscript = String(repeating: "Some text here ", count: 1000)
        
        measure {
            _ = dictionary.relevantTerms(for: veryLongTranscript, limit: 20)
        }
    }
}

// MARK: - Concurrency Tests

@MainActor
final class RewriteConcurrencyTests: XCTestCase {
    
    func testConcurrentDictionaryAccess() async {
        let dictionary = PersonalDictionary.shared
        
        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<10 {
                group.addTask {
                    dictionary.add("ConcurrentTerm\(i)", category: .general)
                }
            }
            
            // Readers
            for _ in 0..<50 {
                group.addTask {
                    _ = dictionary.allTerms
                    _ = dictionary.contains("ConcurrentTerm5")
                }
            }
        }
        
        // All terms should be added
        for i in 0..<10 {
            XCTAssertTrue(dictionary.contains("ConcurrentTerm\(i)"))
        }
    }
}

// MARK: - Memory Tests

final class RewriteMemoryTests: XCTestCase {
    
    func testMemoryUsageWithLargeDictionary() {
        let dictionary = PersonalDictionary.shared
        
        // Add many terms
        let terms = (1...10000).map { "MemoryTestTerm\($0)" }
        dictionary.addTerms(terms, category: .general)
        
        // Memory should not explode
        let allTerms = dictionary.allTerms
        XCTAssertEqual(allTerms.count, 10000)
    }
    
    func testContextEncodingMemory() {
        var contexts: [Data] = []
        
        // Create many contexts
        for i in 0..<1000 {
            let context = RewriteContext(
                appType: .notes,
                recipientContext: "Context \(i) with some additional text to make it realistic",
                styleProfile: StyleProfile.default,
                personalDictionaryTerms: (1...50).map { "DictTerm\($0)" },
                locale: "en-US",
                detectedLanguage: "en"
            )
            
            if let data = try? JSONEncoder().encode(context) {
                contexts.append(data)
            }
        }
        
        XCTAssertEqual(contexts.count, 1000)
    }
}
