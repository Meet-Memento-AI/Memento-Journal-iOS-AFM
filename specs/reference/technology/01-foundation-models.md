# Foundation Models Framework

**Import:** `import FoundationModels`
**Availability:** iOS 26+ (base), substantially expanded iOS 27
**Role in Memento:** the entire intelligence layer. Every generated artifact comes from here.

---

## 1. Mental model

Foundation Models is not "an API for Apple's small model" anymore. As of iOS 27 it is **Swift's general-purpose LLM client**. Behind `LanguageModelSession` sits a *model slot*, not a model. What fills that slot is a runtime decision.

```
LanguageModelSession
  ├── model:        SystemLanguageModel()               ← on-device, free, offline
  │                 PrivateCloudComputeLanguageModel()  ← Apple server, free, quota'd
  │                 CoreAILanguageModel()               ← your own weights, ANE
  │                 MLXLanguageModel()                  ← Hugging Face models, GPU
  │                 <partner packages>                  ← Anthropic, Google
  ├── tools:        [Tool]                              ← model calls back into your code
  ├── instructions: String                              ← system prompt
  └── transcript:   Transcript                          ← conversation history
```

For Memento, only the first two are in scope. The rest exist so the architecture survives if Apple's model quality proves inadequate — see §8.

---

## 2. Basic generation

✅ **VERIFIED** (session 319)

```swift
import FoundationModels

let session = LanguageModelSession()
let response = try await session.respond(to: "Summarize this article: \(article)")
```

Three lines. That is the whole on-device path.

---

## 3. Context size and token counting

✅ **VERIFIED** (sessions 241, 319)

```swift
SystemLanguageModel().contextSize
// 4096 on iOS 26.0
// 8192 on iOS 27.0 (newer devices)

PrivateCloudComputeLanguageModel().contextSize
// 32768

let model = SystemLanguageModel()
let count = try await model.tokenCount(for: "What are the Japanese characters for origami?")
```

`tokenCount(for:)` is available **from iOS 26.4**. ✅ VERIFIED.

**Memento implications — read carefully:**

- **Never hardcode a context budget.** Read `contextSize` at runtime and size your retrieved-entry payload against it.
- 8192 tokens is roughly 25–30 journal entries of moderate length, *before* instructions, tool definitions, and output. On-device weekly reflection must select entries, not dump them. Use `salience` (see the data model) to rank.
- Reasoning tokens count against the limit. A `.deep` reasoning PCC call spends context on thinking before it produces anything.
- The 4096 → 8192 split means **the same code produces different quality on different devices**. Test on the minimum supported Apple Intelligence device, not on your own phone.

---

## 4. Guided generation — `@Generable`

🟡 **LIKELY** (established iOS 26 API, confirmed present in iOS 27 samples)

This is how Memento gets structured output. There is no JSON parsing anywhere in the codebase.

```swift
@Generable
struct ArticleSummary {
    let oneLineSummary: String
    let keyPoints: [String]
}

let response = try await session.respond(
    to: "Summarize this article: \(article)",
    generating: ArticleSummary.self
)
```

✅ VERIFIED that `generating:` works identically on PCC and on-device (session 319).

### `@Guide` annotations

Attach natural-language constraints to individual fields. The model honors them as part of the constrained decoding, not as a suggestion.

```swift
@Generable
struct EntryReflection {
    @Guide(description: "Six words or fewer. No terminal punctuation. Reads naturally aloud.")
    let title: String

    @Guide(description: "Emotional valence from -1.0 (very difficult) to 1.0 (very good).")
    let valence: Double

    @Guide(description: "Up to three moods from the provided vocabulary.")
    let moods: [MoodLabel]        // enum — closed set, see below
}
```

### Enums are the point

**This is the single most important technique in Memento's intelligence layer.** Free-form string tags fragment the Spotlight index, make pattern detection statistically meaningless, and cause the app to claim trends that do not exist.

Every classification field MUST be an enum with a fixed, versioned case set:

```swift
@Generable
enum MoodLabel: String, CaseIterable {
    case anxious, calm, frustrated, hopeful, tired, energized,
         lonely, connected, grieving, content, restless, focused
}
```

Constrained decoding means the model **cannot** emit a value outside the enum. This turns "the model usually returns reasonable tags" into a guarantee.

Stamp the vocabulary version on the entry so a future vocabulary migration can re-tag historical entries.

---

## 5. Tools — letting the model call your code

🟡 **LIKELY** for the protocol shape; ✅ VERIFIED for the usage pattern.

```swift
struct SwitchModeTool: Tool {
    let description = "Switch to a different mode."
    let states: AppStates

    @Generable
    struct Arguments {
        let mode: Mode
    }

    func call(arguments: Arguments) async throws -> some PromptRepresentable {
        states.mode = arguments.mode
        return "Successfully switched to \(arguments.mode)."
    }
}

let session = LanguageModelSession(tools: [SwitchModeTool(states: appStates)])
```

Note the two registration forms seen in Apple samples: instances (`tools: [tool]`) and metatypes (`tools: [FindRelatedArticlesTool.self]`). 🔴 UNVERIFIED which is canonical in the final SDK — check.

### Built-in system tools

✅ VERIFIED (session 241). You get these without writing them:

| Tool | Backed by | Memento use |
|---|---|---|
| `SpotlightSearchTool` | Core Spotlight | **The retrieval layer.** See `03-spotlight-retrieval.md` |
| `OCRTool` | Vision | Text from photo attachments |
| `BarcodeReaderTool` | Vision | Not used — no journaling use case |

### Tool calling mode

🔴 **UNVERIFIED** — secondary sources report `GenerationOptions.ToolCallingMode` in iOS 27 for steering how aggressively the model uses tools. Not seen in Apple sample code reviewed. Verify; if it exists it matters for the Ask surface, where you want the model to *always* search rather than answer from world knowledge.

---

## 6. Vision — image input

✅ **VERIFIED** (session 241)

```swift
let response = try await session.respond {
    "What animal is this?"
    Attachment(UIImage(...))
}
```

Accepts `UIImage`, `NSImage`, `CGImage`, Core Image images, CoreVideo pixel buffers, and file URLs, **at any size**. Larger images cost more tokens. ✅ VERIFIED.

**Memento use:** photo attachments on entries. Generate an on-device description so the photo becomes searchable text in the Spotlight index. This is Z0 — the image never leaves the device. Do **not** send images to PCC.

Note the builder syntax in `respond { }` — that's a result builder taking prompt segments, not a plain string parameter.

---

## 7. Dynamic Profiles — mode switching

✅ **VERIFIED** (session 241). This is new in iOS 27 and it is a strong fit for Memento.

The problem it solves: Memento has two very different generation modes — **reflecting** (Z0, no tools, restrained persona) and **asking** (Z1, Spotlight tool, archivist persona). Traditionally you'd build two sessions and lose conversation history between them. Dynamic Profiles let one session swap instructions, tools, model, *and* reasoning level declaratively.

```swift
struct MementoProfile: LanguageModelSession.DynamicProfile {
    let states: AppStates

    var body: some DynamicProfile {
        switch states.mode {
        case .reflect:
            Profile {
                Instructions { "You are an observer of this person's journal..." }
            }
        case .ask:
            Profile {
                Instructions { "You are an archivist. Report only what the user wrote..." }
                SpotlightSearchTool()
            }
            .model(PrivateCloudComputeLanguageModel())
            .reasoningLevel(.deep)
        }
    }
}

let session = LanguageModelSession(profile: MementoProfile(states: appStates))
```

✅ VERIFIED: modifiers `.model(...)` and `.reasoningLevel(...)` apply per profile branch. A profile resolves to **one active profile at a time**.

### The manual alternative

If Dynamic Profiles prove awkward, the older pattern still works — rebuild the session while preserving history:

```swift
let originalTranscript = session?.transcript.dropFirstInstructions() ?? Transcript()

session = LanguageModelSession(
    tools: [...],
    instructions: "...",
    transcript: originalTranscript
)
```

✅ VERIFIED. `transcript.dropFirstInstructions()` is the key call — it preserves the conversation while discarding the old system prompt.

---

## 8. The model abstraction layer

✅ **VERIFIED** (session 241)

A public `LanguageModel` protocol now backs `LanguageModelSession`. All Apple models conform. Open-source conformances ship as `CoreAILanguageModel` (Neural Engine, your own weights) and `MLXLanguageModel` (Mac GPU, Hugging Face models). Anthropic and Google publish their own conforming Swift packages, with OAuth and Keychain handling for auth and billing, and per-token usage tracking including cache and reasoning tokens.

**Memento's position on this:** the seam exists so the product survives if Apple's model quality is inadequate for reflection. It is **not** licence to ship a third-party provider. Doing so moves the trust boundary from Z1 to Z2, changes the privacy label, and invalidates the positioning claim. Requires an explicit product decision.

**Implementation requirement:** `IntelligenceService` must accept its `LanguageModel` by injection, and the swap must be exercised at least once in a test target so the seam is proven rather than assumed.

---

## 9. Usage inspection

✅ **VERIFIED** (session 241)

```swift
let response = try await session.respond(
    to: "Recommend a craft that doesn't require scissors.",
    contextOptions: ContextOptions(reasoningLevel: .light)
)

response.usage.input.totalTokenCount
response.usage.input.cachedTokenCount
response.usage.output.totalTokenCount
response.usage.output.reasoningTokenCount
```

Use this for local instrumentation of the context budget — especially to detect when retrieved entries are crowding out the reflection itself.

---

## 10. Tooling

✅ VERIFIED (session 241):

- **`fm` CLI** (macOS 27) — `fm chat` for interactive on-device sessions; pipe through it in shell scripts. Useful for rapid prompt iteration without a build.
- **Python SDK** — `import apple_fm_sdk as fm`, same on-device model. Useful for offline prompt evaluation over the fixture corpus.
- **Xcode 27 Foundation Models instrument** — visualizes the whole tool-call loop per request: active instructions, model decisions, time-to-first-token, tokens/sec, total latency. **Use this instead of building custom timing infrastructure.**
- **Framework utilities package** — transcript management, a skill API, chat-completions interfacing. Open source.
- **The core framework is open-sourced** and runs wherever Swift runs, including Linux.
- **Xcode debug option: "Simulate Apple Foundation Models Availability"** — lets you test unavailable and quota-exhausted states. ✅ VERIFIED (session 319). Essential for testing Memento's Reduced tier and degradation paths.

---

## 11. Guardrails

✅ VERIFIED (session 241): iOS 27 "refined guardrails that reduce false positives."

**Memento-specific risk:** journaling is disproportionately likely to contain content that trips safety guardrails — grief, illness, conflict, self-critical language, substance use. A guardrail refusal on a user's own journal entry is a severe experience failure.

Requirements:
- Every generation path MUST handle a guardrail refusal as a **designed state**, not an error alert. Suggested copy: "I don't have an observation for this one." — which coincides with the `hasNothingToSay` design (see §12).
- Log refusal rate against the fixture corpus during evaluation. If it exceeds a few percent, the prompt framing is provoking it.
- Never surface a refusal in a way that implies judgment of what the user wrote.

---

## 12. Memento prompt conventions

Not framework behavior — house rules that every prompt must follow.

1. **No markdown in prose output.** Everything is spoken aloud. See `06-speech-and-audio.md`.
2. **Second person.** "You wrote about..." not "The user wrote about..."
3. **Archivist, not therapist.** Report; do not advise, diagnose, comfort, or ask follow-up questions.
4. **`hasNothingToSay` is a real output.** Every period-reflection schema carries a boolean for "there wasn't enough here to say anything real." When true, the app renders a deliberate empty state and no prose. Silence is a feature.
5. **Ground every claim.** Period reflections return `groundedEntryIDs`. Claims not traceable to an entry are the primary quality failure mode.
6. **Never answer from world knowledge** on the Ask surface. If the corpus doesn't contain it, say so and show what was searched.
7. **Version every prompt.** Persist `promptVersion` and `modelIdentifier` on every generated artifact, or evaluation cannot attribute regressions.
