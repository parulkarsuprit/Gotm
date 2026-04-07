import XCTest
@testable import Gotm

// MARK: - RewriteContext Tests

final class RewriteContextTests: XCTestCase {
    
    // MARK: - Encoding/Decoding
    
    func testRewriteContextEncodingDecoding() throws {
        let profile = StyleProfile(
            oxfordComma: false,
            dashStyle: .en,
            contractionPreference: .always,
            formalityOverrides: ["email": .formal],
            capitalisationOverrides: ["myapp": "MyApp"],
            paragraphFrequency: .sparse,
            listStyle: .bulleted,
            sentenceLengthPreference: .short,
            ellipsisStyle: .dots,
            quotationStyle: .single,
            timeFormat: .twentyFourHour,
            dateFormat: .uk
        )
        
        let context = RewriteContext(
            appType: .email,
            recipientContext: "Reply to engineering team about Q2 planning",
            precedingText: "Let's discuss the roadmap.",
            styleProfile: profile,
            personalDictionaryTerms: ["Kubernetes", "PostgreSQL", "SwiftUI"],
            locale: "en-GB",
            detectedLanguage: "en"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(context)
        let decoded = try decoder.decode(RewriteContext.self, from: data)
        
        XCTAssertEqual(decoded.appType, context.appType)
        XCTAssertEqual(decoded.recipientContext, context.recipientContext)
        XCTAssertEqual(decoded.precedingText, context.precedingText)
        XCTAssertEqual(decoded.locale, context.locale)
        XCTAssertEqual(decoded.detectedLanguage, context.detectedLanguage)
        XCTAssertEqual(decoded.personalDictionaryTerms, context.personalDictionaryTerms)
        
        // Verify style profile
        XCTAssertEqual(decoded.styleProfile?.oxfordComma, profile.oxfordComma)
        XCTAssertEqual(decoded.styleProfile?.dashStyle, profile.dashStyle)
        XCTAssertEqual(decoded.styleProfile?.contractionPreference, profile.contractionPreference)
        XCTAssertEqual(decoded.styleProfile?.paragraphFrequency, profile.paragraphFrequency)
        XCTAssertEqual(decoded.styleProfile?.listStyle, profile.listStyle)
        XCTAssertEqual(decoded.styleProfile?.timeFormat, profile.timeFormat)
        XCTAssertEqual(decoded.styleProfile?.dateFormat, profile.dateFormat)
    }
    
    func testDefaultContext() {
        let context = RewriteContext.default
        
        XCTAssertEqual(context.appType, .notes)
        XCTAssertNil(context.recipientContext)
        XCTAssertNil(context.precedingText)
        XCTAssertNil(context.styleProfile)
        XCTAssertTrue(context.personalDictionaryTerms.isEmpty)
        XCTAssertEqual(context.detectedLanguage, "en")
    }
    
    // MARK: - Request Encoding
    
    func testRewriteRequestEncoding() throws {
        let context = RewriteContext(
            appType: .chat,
            locale: "en-US",
            detectedLanguage: "en"
        )
        
        let endpointMetadata = EndpointMetadata(
            pauseType: .sentenceEnd,
            segmentDurationMs: 3200,
            isContinuation: false,
            confidence: 0.95
        )
        
        let request = RewriteRequest(
            rawTranscript: "um so I was thinking we should meet",
            context: context,
            endpointMetadata: endpointMetadata
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["raw_transcript"] as? String, request.rawTranscript)
        
        let contextDict = json?["context"] as? [String: Any]
        XCTAssertNotNil(contextDict)
        XCTAssertEqual(contextDict?["app_type"] as? String, "chat")
        XCTAssertEqual(contextDict?["locale"] as? String, "en-US")
        
        let endpointDict = json?["endpoint_metadata"] as? [String: Any]
        XCTAssertNotNil(endpointDict)
        XCTAssertEqual(endpointDict?["pause_type"] as? String, "sentence_end")
        XCTAssertEqual(endpointDict?["segment_duration_ms"] as? Int, 3200)
        XCTAssertEqual(endpointDict?["is_continuation"] as? Bool, false)
        XCTAssertEqual(endpointDict?["confidence"] as? Double, 0.95)
    }
}

// MARK: - StyleProfile Tests

final class StyleProfileTests: XCTestCase {
    
    func testDefaultStyleProfile() {
        let profile = StyleProfile.default
        
        XCTAssertTrue(profile.oxfordComma)
        XCTAssertEqual(profile.dashStyle, .em)
        XCTAssertEqual(profile.contractionPreference, .contextDependent)
        XCTAssertTrue(profile.formalityOverrides.isEmpty)
        XCTAssertTrue(profile.capitalisationOverrides.isEmpty)
        XCTAssertEqual(profile.paragraphFrequency, .moderate)
        XCTAssertEqual(profile.listStyle, .inline)
        XCTAssertEqual(profile.sentenceLengthPreference, .mixed)
        XCTAssertEqual(profile.ellipsisStyle, .ellipsis)
        XCTAssertEqual(profile.quotationStyle, .double)
        XCTAssertEqual(profile.timeFormat, .twelveHour)
        XCTAssertEqual(profile.dateFormat, .us)
    }
    
    func testStyleProfileCustomization() {
        var profile = StyleProfile.default
        profile.oxfordComma = false
        profile.dashStyle = .en
        profile.contractionPreference = .never
        profile.paragraphFrequency = .dense
        profile.timeFormat = .twentyFourHour
        
        XCTAssertFalse(profile.oxfordComma)
        XCTAssertEqual(profile.dashStyle, .en)
        XCTAssertEqual(profile.contractionPreference, .never)
        XCTAssertEqual(profile.paragraphFrequency, .dense)
        XCTAssertEqual(profile.timeFormat, .twentyFourHour)
    }
    
    func testFormalityOverrides() {
        var profile = StyleProfile.default
        profile.formalityOverrides = [
            "email": .formal,
            "chat": .casual,
            "document": .professionalCasual
        ]
        
        XCTAssertEqual(profile.formalityOverrides["email"], .formal)
        XCTAssertEqual(profile.formalityOverrides["chat"], .casual)
        XCTAssertEqual(profile.formalityOverrides["document"], .professionalCasual)
        XCTAssertNil(profile.formalityOverrides["notes"])
    }
    
    func testCapitalisationOverrides() {
        var profile = StyleProfile.default
        profile.capitalisationOverrides = [
            "ios": "iOS",
            "macos": "macOS",
            "github": "GitHub"
        ]
        
        XCTAssertEqual(profile.capitalisationOverrides["ios"], "iOS")
        XCTAssertEqual(profile.capitalisationOverrides["macos"], "macOS")
        XCTAssertEqual(profile.capitalisationOverrides["github"], "GitHub")
    }
}

// MARK: - AppType Tests

final class AppTypeTests: XCTestCase {
    
    func testAllAppTypes() {
        let allTypes: [AppType] = [.notes, .chat, .email, .document, .code, .search]
        
        XCTAssertEqual(allTypes.count, 6)
        
        for type in allTypes {
            XCTAssertEqual(AppType(rawValue: type.rawValue), type)
        }
    }
    
    func testAppTypeDisplayNames() {
        XCTAssertEqual(AppType.notes.displayName, "Notes")
        XCTAssertEqual(AppType.chat.displayName, "Chat")
        XCTAssertEqual(AppType.email.displayName, "Email")
        XCTAssertEqual(AppType.document.displayName, "Document")
        XCTAssertEqual(AppType.code.displayName, "Code")
        XCTAssertEqual(AppType.search.displayName, "Search")
    }
}
