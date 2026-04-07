# Dictation Rewrite System Tests

This directory contains comprehensive tests for the Gotm dictation cleanup system.

## Test Structure

| File | Description |
|------|-------------|
| `RewriteContextTests.swift` | Tests for context encoding, style profiles, and app types |
| `PersonalDictionaryTests.swift` | Tests for dictionary CRUD, relevance scoring, and learning |
| `TranscriptionServiceTests.swift` | Tests for garbage detection and edge cases from design doc |
| `RewritePerformanceTests.swift` | Performance, stress, and concurrency tests |
| `TestUtilities.swift` | Shared utilities, mock services, and helpers |

## Running Tests

### In Xcode
1. Select the test scheme (GotmTests)
2. Use Cmd+U to run all tests
3. Or select specific test files and use the test navigator

### Command Line
```bash
# Run all tests
xcodebuild test -project Gotm.xcodeproj -scheme Gotm -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
xcodebuild test -project Gotm.xcodeproj -scheme Gotm -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GotmTests/RewriteContextTests
```

## Test Categories

### Unit Tests
- **Encoding/Decoding**: Verify JSON serialization of contexts and requests
- **CRUD Operations**: Test dictionary add/remove/update
- **Validation**: Test transcript validity and garbage response detection

### Edge Case Tests (from Design Document)
- Category 1: Tricky filler vs meaningful words ("like", "literally")
- Category 2: Self-correction resolution ("X no Y", "X wait Y")
- Category 3: Punctuation challenges (direct vs indirect questions)
- Category 4: Number and data formatting
- Category 5: Context-sensitive tone (email vs chat)
- Category 6: Spoken punctuation commands
- Category 9: Edge cases that break naive implementations

### Performance Tests
- Dictionary lookup performance (1,000+ terms)
- Relevance scoring performance
- JSON encoding performance
- Memory usage with large dictionaries

### Stress Tests
- Large personal dictionary (10,000 terms)
- Repeated add operations
- Very long transcripts

### Concurrency Tests
- Concurrent dictionary access
- Thread-safe operations

## Adding New Tests

### Basic Test Structure
```swift
func testSomething() {
    // Arrange
    let input = "test input"
    
    // Act
    let result = transform(input)
    
    // Assert
    XCTAssertEqual(result, expected)
}
```

### Async Test Structure
```swift
func testAsyncOperation() async {
    // Arrange
    let service = TranscriptionService.shared
    
    // Act
    let result = await service.formatWithAI("input", context: .default)
    
    // Assert
    XCTAssertNotNil(result)
}
```

### Performance Test Structure
```swift
func testPerformance() {
    measure {
        // Code to measure
        for _ in 0..<100 {
            operation()
        }
    }
}
```

## Test Data

### Sample Transcripts
Located in `RewriteTestUtilities.sampleTranscripts`:
- Filler words with corrections
- Repetitions
- Time and date formats
- Currency formats

### Mock Services
- `MockTranscriptionService`: Simulates transcription without network
- `MockPersonalDictionary`: Isolated dictionary for testing

## Expected Behavior

### Garbage Response Detection
The following should be detected as garbage:
- Refusal prefixes: "I'm sorry", "I cannot", "As an AI"
- Leaked instructions: "FILLER WORD REMOVAL", "Self-correction resolution"
- Responses >4x original length
- Responses <30% of original length (for inputs >50 chars)

### Valid Transcript Detection
Valid transcripts must:
- Have at least 2 words >1 character
- Not be common hallucinations ("you", "thanks", "ok")
- Not be pure noise markers

### Context-Aware Formatting
| App Type | Contractions | Fillers | Tone |
|----------|-------------|---------|------|
| notes | keep | moderate | natural |
| chat | keep | light | casual |
| email | reduce | aggressive | professional |
| document | reduce | aggressive | formal |
| code | keep | minimal | conservative |
| search | keep | minimal | raw |

## Debugging Failed Tests

1. **Check test isolation**: Each test should be independent
2. **Verify MainActor**: Dictionary tests need `@MainActor`
3. **Check async/await**: Use proper async test patterns
4. **Review logs**: Check console for detailed error messages

## Continuous Integration

Tests run automatically on:
- Pull request creation
- Merge to main branch
- Nightly builds

Test results are available in:
- Xcode Test Navigator
- Command line output
- CI pipeline reports
