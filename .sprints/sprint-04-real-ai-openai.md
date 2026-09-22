# Sprint 4: Real AI Integration (OpenAI)

**Status**: ⏳ Blocked by Sprint 3 + **Waiting for User's OpenAI Code**
**Duration**: 3-4 days
**Sprint Goal**: Replace mock insights with real OpenAI-generated insights

---

## 🎯 Objectives

1. Integrate OpenAI API for real AI insights
2. Implement prompt engineering for quality insights
3. Handle API errors and rate limits gracefully
4. Optimize for cost efficiency
5. Track token usage

---

## 📋 Prerequisites

### User Will Provide:
- ⏳ **OpenAI API code/implementation**
- ⏳ **Prompt templates for insights**
- ⏳ **Configuration details (model, temperature, etc.)**

### Before Starting:
- [ ] Receive OpenAI code from user
- [ ] Review provided implementation
- [ ] Understand prompt structure
- [ ] Get API key setup instructions
- [ ] Sprint 3 completed (mock AI working)

---

## 📋 Tasks Breakdown

### Task 4.1: Review User's OpenAI Code (1 hour)

**What to Check**:
- [ ] Which OpenAI model is used? (GPT-4, GPT-3.5-turbo, etc.)
- [ ] How is the API called? (direct API or SDK)
- [ ] What's the prompt structure?
- [ ] How are responses parsed?
- [ ] What error handling exists?
- [ ] Token counting implementation?

**Questions to Ask User**:
1. Which OpenAI Swift library are you using?
2. Do you have example prompts for journal analysis?
3. What's the expected response format?
4. Any specific model configuration? (temperature, max_tokens)
5. Cost considerations per API call?

### Task 4.2: Set Up OpenAI Configuration (1 hour)

**File**: `withMemento/Resources/Config.swift` or `OpenAIConfig.swift`

- [ ] Add OpenAI API key storage
- [ ] Add model configuration (model name, temperature)
- [ ] Add token limits (max_tokens per request)
- [ ] Add timeout settings
- [ ] Never commit API key to git

**Config Structure**:
```swift
struct OpenAIConfig {
    static let apiKey = "YOUR_OPENAI_API_KEY" // From environment or keychain
    static let model = "gpt-4" // or gpt-3.5-turbo
    static let temperature: Double = 0.7
    static let maxTokens = 500
    static let timeout: TimeInterval = 30
}
```

**Security**:
- [ ] Add to `.gitignore` if storing in file
- [ ] Or use environment variables
- [ ] Or use iOS Keychain
- [ ] Never hardcode in source

### Task 4.3: Create OpenAI Service Wrapper (2-3 hours)

**File**: `withMemento/Services/OpenAIService.swift`

- [ ] Create `OpenAIService` class
- [ ] Implement chat completion method
- [ ] Add request/response models
- [ ] Add error handling
- [ ] Add retry logic (for rate limits)
- [ ] Add token counting
- [ ] Add logging

**Service Structure**:
```swift
class OpenAIService {
    static let shared = OpenAIService()

    // Based on user's code, might look like:
    func generateInsights(from entries: [Entry]) async throws -> InsightResponse
    func countTokens(for text: String) -> Int
    func handleRateLimit(error: Error) async throws
}
```

### Task 4.4: Implement Prompt Engineering (2-3 hours)

**Based on User's Prompts**

- [ ] Create system prompt for insights generation
- [ ] Create user prompt with entry data
- [ ] Optimize prompt length (reduce tokens)
- [ ] Include formatting instructions
- [ ] Test prompt variations
- [ ] Ensure consistent JSON response

**Prompt Template Example** (adjust based on user's code):
```swift
let systemPrompt = """
You are an empathetic AI journal analyst. Analyze journal entries and provide:
1. A summary title (1 sentence)
2. A detailed summary paragraph (2-3 sentences)
3. A list of 3-4 key themes

Be compassionate, insightful, and concise.
"""

let userPrompt = """
Analyze these \(entries.count) journal entries:

\(entries.map { "[\($0.createdAt)]: \($0.text)" }.joined(separator: "\n\n"))

Provide analysis in JSON format:
{
  "summary": {
    "title": "...",
    "body": "..."
  },
  "themes": ["...", "...", "..."]
}
"""
```

### Task 4.5: Integrate into InsightsViewModel (2 hours)

**File**: `withMemento/ViewModels/InsightsViewModel.swift`

- [ ] Import OpenAIService
- [ ] Replace mock `generateInsights()` with real implementation
- [ ] Call OpenAI API
- [ ] Parse response
- [ ] Handle API errors
- [ ] Add retry logic
- [ ] Maintain loading states

**Integration**:
```swift
private func generateInsights(entries: [Entry]) async throws -> JournalInsights {
    guard !entries.isEmpty else {
        throw InsightsError.noEntries
    }

    // Call OpenAI based on user's provided code
    let response = try await OpenAIService.shared.generateInsights(from: entries)

    // Parse response to JournalInsights
    return JournalInsights(
        summary: response.summary,
        themes: response.themes,
        generatedAt: Date(),
        entriesAnalyzed: entries.count
    )
}
```

### Task 4.6: Handle Rate Limits (1 hour)

**OpenAI Rate Limits**:
- RPM (Requests Per Minute)
- TPM (Tokens Per Minute)
- RPD (Requests Per Day)

- [ ] Detect rate limit errors
- [ ] Implement exponential backoff
- [ ] Show user-friendly message
- [ ] Queue requests if needed
- [ ] Add retry after delay

**Error Handling**:
```swift
if error.isRateLimitError {
    // Wait and retry
    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
    return try await generateInsights(entries: entries)
}
```

### Task 4.7: Optimize Token Usage (1 hour)

**Cost Optimization**:
- [ ] Limit entry text length (first 500 chars per entry)
- [ ] Summarize very long entries before sending
- [ ] Cache aggressively (7+ days)
- [ ] Batch multiple requests if possible
- [ ] Use cheaper model for simple tasks

**Token Reduction**:
```swift
// Truncate long entries
let truncatedEntries = entries.map { entry in
    Entry(
        id: entry.id,
        title: entry.title,
        text: String(entry.text.prefix(500)), // Max 500 chars
        createdAt: entry.createdAt
    )
}
```

### Task 4.8: Add Token Tracking (1 hour)

- [ ] Log tokens used per request
- [ ] Track total tokens per user
- [ ] Calculate cost per request
- [ ] Add to cache metadata
- [ ] Create analytics for monitoring

**Tracking**:
```swift
let tokensUsed = countTokens(prompt) + countTokens(response)
let estimatedCost = (tokensUsed / 1000.0) * 0.002 // $0.002 per 1K tokens (GPT-3.5)

print("💰 API Call: \(tokensUsed) tokens, ~$\(String(format: "%.4f", estimatedCost))")
```

### Task 4.9: Error Handling & Fallbacks (2 hours)

**Error Types to Handle**:
- [ ] Network errors (no internet)
- [ ] Authentication errors (invalid API key)
- [ ] Rate limit errors (429)
- [ ] Timeout errors
- [ ] Invalid response format
- [ ] Token limit exceeded

**Fallback Strategy**:
```swift
do {
    return try await generateWithOpenAI(entries)
} catch let error as OpenAIError {
    switch error {
    case .rateLimitExceeded:
        throw InsightsError.rateLimited(retryAfter: "5 minutes")
    case .invalidAPIKey:
        throw InsightsError.configurationError
    case .networkError:
        throw InsightsError.networkUnavailable
    default:
        // Fallback to simple keyword analysis?
        return generateBasicInsights(entries)
    }
}
```

### Task 4.10: Testing & Validation (2 hours)

**Test Cases**:
- [ ] Small entry set (1-3 entries)
- [ ] Medium entry set (5-10 entries)
- [ ] Large entry set (20+ entries)
- [ ] Very long entries (5000+ chars)
- [ ] Entries with special characters
- [ ] Entries in different languages (if supported)

**Validation**:
- [ ] Response format is correct
- [ ] Summary makes sense
- [ ] Themes are relevant
- [ ] No hallucinations
- [ ] Consistent quality

---

## ✅ Acceptance Criteria

### Functionality:
- [ ] OpenAI API calls succeed
- [ ] Insights are relevant to journal content
- [ ] Response parsing works consistently
- [ ] Cache saves AI-generated insights
- [ ] Second load uses cache (no API call)

### Error Handling:
- [ ] Network errors handled gracefully
- [ ] Rate limits don't crash app
- [ ] Invalid responses handled
- [ ] Timeout errors handled
- [ ] User sees helpful error messages

### Performance:
- [ ] First generation: 2-5 seconds
- [ ] Cached load: < 100ms
- [ ] Token usage optimized
- [ ] Cost per user acceptable

### Quality:
- [ ] Insights are contextually relevant
- [ ] Summary captures key themes
- [ ] Themes match journal content
- [ ] Tone is empathetic
- [ ] No hallucinations or made-up facts

---

## 🧪 Testing Checklist

### Integration Tests:

1. **API Connection**:
   - [ ] Valid API key works
   - [ ] Invalid API key fails gracefully
   - [ ] Network error handled

2. **Prompt & Response**:
   - [ ] Prompt includes entry data
   - [ ] Response format is JSON
   - [ ] Response parsed correctly
   - [ ] Summary extracted
   - [ ] Themes extracted

3. **Caching**:
   - [ ] First call generates new insights
   - [ ] Subsequent calls use cache
   - [ ] Cache saves AI response
   - [ ] No unnecessary API calls

4. **Error Scenarios**:
   - [ ] Rate limit → retry works
   - [ ] Timeout → error message
   - [ ] Invalid response → fallback or error
   - [ ] Network down → error message

### Cost Analysis:

- [ ] Calculate tokens per request
- [ ] Estimate cost per user per month
- [ ] Verify cache reduces costs 80-90%
- [ ] Monitor token usage in logs

**Example Calculation**:
```
Prompt: ~300 tokens
Response: ~200 tokens
Total: 500 tokens per request

With cache (7-day TTL):
- 1 request per week per user
- 4 requests per month
- 2000 tokens per month per user
- Cost: $0.004/month per user (GPT-3.5)
```

---

## 📦 Deliverables

### Files Created/Modified:

```
withMemento/
├── Services/
│   └── OpenAIService.swift (NEW)
├── ViewModels/
│   └── InsightsViewModel.swift (UPDATE - use OpenAI)
└── Resources/
    └── OpenAIConfig.swift (NEW)
```

### Components Delivered:
- ✅ OpenAI service wrapper
- ✅ Prompt engineering
- ✅ Response parsing
- ✅ Error handling
- ✅ Rate limit handling
- ✅ Token tracking
- ✅ Cost optimization

---

## 💰 Cost Analysis

### OpenAI Pricing (as of 2025):
- **GPT-4**: $0.03 per 1K input tokens, $0.06 per 1K output tokens
- **GPT-3.5-turbo**: $0.0015 per 1K input tokens, $0.002 per 1K output tokens

### Estimated Costs Per User:

**Without Caching**:
- Open insights tab: 1 API call
- 10 times per day: 10 API calls
- 300 API calls per month
- 150,000 tokens per month
- **Cost: ~$0.30/month (GPT-3.5) or ~$9/month (GPT-4)**

**With Caching (7-day TTL)**:
- First load: 1 API call
- Next 6 days: cached (0 API calls)
- 4-5 API calls per month
- 2,500 tokens per month
- **Cost: ~$0.005/month (GPT-3.5) or ~$0.15/month (GPT-4)**

**Savings: 95% reduction in API costs!** 💰

---

## 📝 Notes for User's OpenAI Code

### Questions to Clarify:

1. **Which library?**
   - OpenAI official Swift SDK?
   - Custom URLSession implementation?
   - Third-party wrapper?

2. **Response format?**
   - JSON structured?
   - Plain text that needs parsing?
   - Streaming or single response?

3. **Model choice?**
   - GPT-4 (better quality, expensive)
   - GPT-3.5-turbo (fast, cheap)
   - GPT-4-turbo (balanced)

4. **Prompt style?**
   - System + User messages?
   - Single user message?
   - Few-shot examples included?

### Integration Points:

**Where User's Code Fits**:
```swift
// In InsightsViewModel.swift

private func generateInsights(entries: [Entry]) async throws -> JournalInsights {
    // 1. Prepare data
    let entryTexts = entries.map { $0.text }

    // 2. USER'S OPENAI CODE GOES HERE
    let aiResponse = try await yourOpenAIImplementation(entries: entryTexts)

    // 3. Parse to JournalInsights format
    return parseResponse(aiResponse)
}
```

---

## 🔗 References

- **OpenAI API Docs**: https://platform.openai.com/docs/api-reference
- **Swift SDK**: https://github.com/MacPaw/OpenAI (if using)
- **Token Counting**: https://platform.openai.com/tokenizer
- **Rate Limits**: https://platform.openai.com/docs/guides/rate-limits

---

## 🚀 Getting Started

### Step 1: Wait for User's Code
- [ ] Receive OpenAI implementation from user
- [ ] Review code structure
- [ ] Understand prompt format
- [ ] Check model configuration

### Step 2: Integration
- [ ] Copy user's OpenAI code
- [ ] Adapt to InsightsViewModel
- [ ] Test with sample entries
- [ ] Verify response parsing

### Step 3: Testing
- [ ] Test with real journal entries
- [ ] Validate insights quality
- [ ] Check token usage
- [ ] Monitor costs

---

**Prerequisites**:
- ✅ Sprint 3 complete (mock AI working)
- ⏳ User provides OpenAI code/implementation
- ⏳ OpenAI API key configured

**Estimated Time**: 3-4 days (after receiving code)
**Complexity**: High

---

**Status**: ⏳ **Waiting for user to provide OpenAI code and prompts**

Please share:
1. Your OpenAI API integration code
2. Prompt templates you want to use
3. Model configuration (GPT-4, GPT-3.5, etc.)
4. Any specific requirements or constraints
