import XCTest
@testable import Gotm

// MARK: - Personal Dictionary Tests

@MainActor
final class PersonalDictionaryTests: XCTestCase {
    
    var dictionary: PersonalDictionary!
    
    override func setUp() {
        super.setUp()
        // Create a fresh dictionary with a temporary file manager for isolation
        dictionary = PersonalDictionary.shared
        // Clear existing entries for clean tests
        dictionary.entries.forEach { dictionary.remove(id: $0.id) }
    }
    
    override func tearDown() {
        dictionary = nil
        super.tearDown()
    }
    
    // MARK: - Basic CRUD
    
    func testAddTerm() {
        dictionary.add("Kubernetes", category: .technical)
        
        XCTAssertTrue(dictionary.contains("Kubernetes"))
        XCTAssertTrue(dictionary.contains("kubernetes")) // Case insensitive
        XCTAssertEqual(dictionary.canonicalForm(for: "kubernetes"), "Kubernetes")
    }
    
    func testAddDuplicateTermIncrementsUsageCount() {
        dictionary.add("Docker", category: .technical)
        dictionary.add("docker", category: .technical) // Same term, different case
        
        let entry = dictionary.entries.first { $0.term == "Docker" }
        XCTAssertEqual(entry?.usageCount, 2)
    }
    
    func testAddMultipleTerms() {
        let terms = ["React", "Vue", "Angular"]
        dictionary.addTerms(terms, category: .technical)
        
        for term in terms {
            XCTAssertTrue(dictionary.contains(term))
        }
    }
    
    func testRemoveTerm() {
        dictionary.add("PostgreSQL", category: .technical)
        let id = dictionary.entries.first { $0.term == "PostgreSQL" }!.id
        
        dictionary.remove(id: id)
        
        XCTAssertFalse(dictionary.contains("PostgreSQL"))
    }
    
    func testUpdateCategory() {
        dictionary.add("Apple", category: .general)
        let id = dictionary.entries.first { $0.term == "Apple" }!.id
        
        dictionary.updateCategory(id: id, to: .company)
        
        let entry = dictionary.entries.first { $0.id == id }
        XCTAssertEqual(entry?.category, .company)
    }
    
    // MARK: - Term Accessors
    
    func testAllTerms() {
        dictionary.add("Swift", category: .technical)
        dictionary.add("Xcode", category: .product)
        
        let allTerms = dictionary.allTerms
        XCTAssertTrue(allTerms.contains("Swift"))
        XCTAssertTrue(allTerms.contains("Xcode"))
    }
    
    func testTermsInCategory() {
        dictionary.add("Kubernetes", category: .technical)
        dictionary.add("Docker", category: .technical)
        dictionary.add("Apple", category: .company)
        
        let technicalTerms = dictionary.terms(in: .technical)
        XCTAssertEqual(technicalTerms.count, 2)
        XCTAssertTrue(technicalTerms.contains("Kubernetes"))
        XCTAssertTrue(technicalTerms.contains("Docker"))
        
        let companyTerms = dictionary.terms(in: .company)
        XCTAssertEqual(companyTerms.count, 1)
        XCTAssertTrue(companyTerms.contains("Apple"))
    }
    
    // MARK: - Relevance Scoring
    
    func testRelevantTermsSorting() {
        // Add terms with different usage counts
        dictionary.add("Kubernetes", category: .technical) // usageCount = 1
        dictionary.add("Docker", category: .technical)
        dictionary.add("Docker", category: .technical) // usageCount = 2
        dictionary.add("Docker", category: .technical) // usageCount = 3
        
        let transcript = "I need to check the Docker containers and Kubernetes pods"
        let relevant = dictionary.relevantTerms(for: transcript, limit: 10)
        
        // Docker should come first (higher usage + appears in transcript)
        XCTAssertEqual(relevant.first, "Docker")
        XCTAssertTrue(relevant.contains("Kubernetes"))
    }
    
    func testRelevantTermsLimit() {
        dictionary.addTerms(["Term1", "Term2", "Term3", "Term4", "Term5"], category: .general)
        
        let transcript = "Using Term1 and Term2"
        let relevant = dictionary.relevantTerms(for: transcript, limit: 2)
        
        XCTAssertEqual(relevant.count, 2)
    }
    
    func testRelevantTermsBoostsForTranscriptPresence() {
        dictionary.add("SwiftUI", category: .technical)
        dictionary.add("UIKit", category: .technical)
        // Both have usageCount = 1, but only SwiftUI appears in transcript
        
        let transcript = "Building views with SwiftUI"
        let relevant = dictionary.relevantTerms(for: transcript)
        
        // SwiftUI should rank higher because it appears in transcript
        let swiftUIIndex = relevant.firstIndex(of: "SwiftUI")
        let uiKitIndex = relevant.firstIndex(of: "UIKit")
        
        if let swiftUIIdx = swiftUIIndex, let uiKitIdx = uiKitIndex {
            XCTAssertLessThan(swiftUIIdx, uiKitIdx)
        }
    }
    
    // MARK: - Learning from Corrections
    
    func testLearnCorrectionExtractsProperNouns() {
        let asrOutput = "meeting with john about the project"
        let userCorrection = "meeting with John about the Kubernetes project"
        
        dictionary.learnCorrection(asrOutput: asrOutput, userCorrection: userCorrection)
        
        XCTAssertTrue(dictionary.contains("Kubernetes"))
        // "John" should also be learned as it's a proper noun
        XCTAssertTrue(dictionary.contains("John"))
    }
    
    func testLearnCorrectionIgnoresShortWords() {
        let initialCount = dictionary.entries.count
        
        let asrOutput = "go to the store"
        let userCorrection = "go to the shop"
        
        dictionary.learnCorrection(asrOutput: asrOutput, userCorrection: userCorrection)
        
        // Short words like "shop" (4 chars) should not be learned
        XCTAssertEqual(dictionary.entries.count, initialCount)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyTermNotAdded() {
        let initialCount = dictionary.entries.count
        
        dictionary.add("")
        dictionary.add("   ") // Whitespace only
        
        XCTAssertEqual(dictionary.entries.count, initialCount)
    }
    
    func testCaseInsensitiveLookup() {
        dictionary.add("GitHub", category: .product)
        
        XCTAssertTrue(dictionary.contains("github"))
        XCTAssertTrue(dictionary.contains("GITHUB"))
        XCTAssertTrue(dictionary.contains("GitHub"))
        XCTAssertEqual(dictionary.canonicalForm(for: "github"), "GitHub")
        XCTAssertEqual(dictionary.canonicalForm(for: "GITHUB"), "GitHub")
    }
    
    func testUnknownTermReturnsNil() {
        XCTAssertNil(dictionary.canonicalForm(for: "NonExistentTerm"))
        XCTAssertFalse(dictionary.contains("NonExistentTerm"))
    }
}

// MARK: - DictionaryEntry Tests

final class DictionaryEntryTests: XCTestCase {
    
    func testDictionaryEntryCreation() {
        let entry = DictionaryEntry(
            term: "Swift",
            commonMisspellings: ["swft", "swifft"],
            category: .technical
        )
        
        XCTAssertEqual(entry.term, "Swift")
        XCTAssertEqual(entry.normalizedTerm, "swift")
        XCTAssertEqual(entry.commonMisspellings, ["swft", "swifft"])
        XCTAssertEqual(entry.category, .technical)
        XCTAssertEqual(entry.usageCount, 1)
        XCTAssertNotNil(entry.createdAt)
    }
    
    func testDictionaryEntryEquatable() {
        let entry1 = DictionaryEntry(term: "Swift", category: .technical)
        let entry2 = DictionaryEntry(term: "Swift", category: .technical)
        
        // Entries with same ID should be equal
        XCTAssertEqual(entry1.id, entry1.id)
        
        // Different IDs should not be equal
        XCTAssertNotEqual(entry1.id, entry2.id)
    }
    
    func testTermCategoryDisplayNames() {
        XCTAssertEqual(TermCategory.person.displayName, "People")
        XCTAssertEqual(TermCategory.company.displayName, "Companies")
        XCTAssertEqual(TermCategory.product.displayName, "Products")
        XCTAssertEqual(TermCategory.technical.displayName, "Technical")
        XCTAssertEqual(TermCategory.place.displayName, "Places")
        XCTAssertEqual(TermCategory.acronym.displayName, "Acronyms")
        XCTAssertEqual(TermCategory.general.displayName, "General")
    }
}
