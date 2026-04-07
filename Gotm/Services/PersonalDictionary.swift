import Foundation

// MARK: - Personal Dictionary Entry

/// A term in the user's personal dictionary.
/// Used to correct ASR errors and enforce specific casing.
struct DictionaryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var commonMisspellings: [String]
    var category: TermCategory
    var createdAt: Date
    var usageCount: Int
    
    init(
        id: UUID = UUID(),
        term: String,
        commonMisspellings: [String] = [],
        category: TermCategory = .general,
        usageCount: Int = 1
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = term.lowercased()
        self.commonMisspellings = commonMisspellings
        self.category = category
        self.createdAt = Date()
        self.usageCount = usageCount
    }
}

enum TermCategory: String, Codable, CaseIterable {
    case person = "person"           // Names, contacts
    case company = "company"         // Company names
    case product = "product"         // Product names
    case technical = "technical"     // APIs, frameworks, tools
    case place = "place"             // Locations
    case acronym = "acronym"         // Custom acronyms
    case general = "general"         // Other terms
    
    var displayName: String {
        switch self {
        case .person: return "People"
        case .company: return "Companies"
        case .product: return "Products"
        case .technical: return "Technical"
        case .place: return "Places"
        case .acronym: return "Acronyms"
        case .general: return "General"
        }
    }
}

// MARK: - Personal Dictionary Service

/// Manages the user's personal dictionary for ASR correction.
/// Terms are learned from user corrections and manual additions.
@MainActor
final class PersonalDictionary: ObservableObject {
    static let shared = PersonalDictionary()
    
    @Published private(set) var entries: [DictionaryEntry] = []
    
    private let fileManager: FileManager
    private let saveFileName = "personal_dictionary.json"
    
    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        load()
    }
    
    // MARK: - Accessors
    
    /// All terms as strings for the AI formatter
    var allTerms: [String] {
        entries.map { $0.term }
    }
    
    /// Terms for a specific category
    func terms(in category: TermCategory) -> [String] {
        entries
            .filter { $0.category == category }
            .map { $0.term }
    }
    
    /// Check if a term exists (case-insensitive)
    func contains(_ term: String) -> Bool {
        let normalized = term.lowercased()
        return entries.contains { $0.normalizedTerm == normalized }
    }
    
    /// Get the canonical form of a term (case-corrected)
    func canonicalForm(for term: String) -> String? {
        let normalized = term.lowercased()
        return entries.first { $0.normalizedTerm == normalized }?.term
    }
    
    // MARK: - Modification
    
    /// Add a new term or increment usage of existing term
    func add(_ term: String, category: TermCategory = .general, misspellings: [String] = []) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let normalized = trimmed.lowercased()
        
        if let index = entries.firstIndex(where: { $0.normalizedTerm == normalized }) {
            // Increment usage count for existing term
            let existing = entries[index]
            updated.usageCount += 1
            entries[index] = updated
        } else {
            // Add new entry
            let entry = DictionaryEntry(
                term: trimmed,
                commonMisspellings: misspellings,
                category: category
            )
            entries.append(entry)
        }
        
        save()
    }
    
    /// Add multiple terms at once
    func addTerms(_ terms: [String], category: TermCategory = .general) {
        for term in terms {
            add(term, category: category)
        }
    }
    
    /// Remove a term
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }
    
    /// Update a term's category
    func updateCategory(id: UUID, to category: TermCategory) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries[index]
        // Since category isn't a var, we need to create new entry
        let newEntry = DictionaryEntry(
            id: existing.id,
            term: existing.term,
            commonMisspellings: existing.commonMisspellings,
            category: category,
            usageCount: existing.usageCount
        )
        entries[index] = newEntry
        save()
    }
    
    /// Learn from a user correction (ASR output → user-edited output)
    func learnCorrection(asrOutput: String, userCorrection: String) {
        // Extract words that differ significantly
        _ = asrOutput.split(separator: " ").map(String.init)
        let userWords = userCorrection.split(separator: " ").map(String.init)
        
        // Simple heuristic: find words in user correction not in ASR
        for word in userWords {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            guard cleanWord.count > 2 else { continue }
            
            // Check if this looks like a proper noun (capitalized) or technical term
            let isProperNoun = cleanWord.first?.isUppercase == true
            let looksTechnical = cleanWord.contains { $0.isUppercase } && cleanWord.count > 3
            
            if isProperNoun || looksTechnical {
                let category: TermCategory = looksTechnical ? .technical : .general
                add(cleanWord, category: category, misspellings: [])
            }
        }
    }
    
    /// Get terms relevant to a transcript (for passing to AI formatter)
    func relevantTerms(for transcript: String, limit: Int = 20) -> [String] {
        let transcriptLower = transcript.lowercased()
        
        // Score entries by relevance
        let scored = entries.map { entry -> (entry: DictionaryEntry, score: Int) in
            var score = entry.usageCount // Base score from usage
            
            // Boost if term appears in transcript
            if transcriptLower.contains(entry.normalizedTerm) {
                score += 10
            }
            
            // Boost if any misspelling appears
            for misspelling in entry.commonMisspellings {
                if transcriptLower.contains(misspelling.lowercased()) {
                    score += 5
                }
            }
            
            return (entry, score)
        }
        
        // Return top terms by score
        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.entry.term }
    }
    
    // MARK: - Persistence
    
    private func dictionaryFileURL() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: saveFileName)
    }
    
    private func load() {
        let url = dictionaryFileURL()
        guard let data = try? Data(contentsOf: url) else {
            // Initialize with common tech terms
            loadDefaultTerms()
            return
        }
        
        do {
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            print("❌ [PersonalDictionary] Failed to load: \(error)")
            loadDefaultTerms()
        }
    }
    
    private func save() {
        let url = dictionaryFileURL()
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ [PersonalDictionary] Failed to save: \(error)")
        }
    }
    
    private func loadDefaultTerms() {
        // Seed with common terms that ASR often gets wrong
        let defaults: [(String, TermCategory)] = [
            // Technical terms
            ("Kubernetes", .technical),
            ("Docker", .technical),
            ("PostgreSQL", .technical),
            ("MongoDB", .technical),
            ("Redis", .technical),
            ("Elasticsearch", .technical),
            ("GraphQL", .technical),
            ("TypeScript", .technical),
            ("JavaScript", .technical),
            ("React", .technical),
            ("SwiftUI", .technical),
            ("Swift", .technical),
            ("iOS", .product),
            ("macOS", .product),
            ("iPhone", .product),
            ("iPad", .product),
            ("GitHub", .product),
            ("GitLab", .product),
            ("AWS", .technical),
            ("GCP", .technical),
            ("Azure", .technical),
            // Common acronyms
            ("API", .acronym),
            ("REST", .acronym),
            ("JSON", .acronym),
            ("SQL", .acronym),
            ("HTML", .acronym),
            ("CSS", .acronym),
            ("URL", .acronym),
            ("SDK", .acronym),
            ("UI", .acronym),
            ("UX", .acronym),
            ("PR", .acronym),
            ("QA", .acronym),
            ("CEO", .acronym),
            ("CTO", .acronym),
            ("PM", .acronym),
        ]
        
        for (term, category) in defaults {
            entries.append(DictionaryEntry(term: term, category: category))
        }
        
        save()
    }
}
