# Core Spotlight + SpotlightSearchTool — the retrieval layer

**Imports:** `import CoreSpotlight`, `import FoundationModels`
**Availability:** `SpotlightSearchTool` — iOS 27, iPadOS 27, macOS 27, visionOS 27. ✅ VERIFIED. **Note: not watchOS.**
**Role in Memento:** replaces the entire pgvector + embeddings + retrieval-endpoint stack from v1.3.

---

## 1. Mental model

Stop thinking about retrieval as a pipeline you build. The new model is:

> **Donate your content to Core Spotlight. Hand the model a tool. The model writes its own queries, Spotlight runs them, the model reasons over the results.**

Apple's own framing from session 246: *stop writing search queries, provide the content and let intelligence do the rest.*

What this deletes from Memento 1.3:
- pgvector tables — gone
- Chunking strategy — gone
- `text-embedding-004` calls — gone
- Similarity thresholds — gone
- Retrieval Edge Function — gone
- The entire Supabase tier — gone

What replaces it: correct donation, a well-scoped guidance profile, and an index delegate.

**Prerequisite:** the app must donate searchable content with Core Spotlight. Apple names the prior-year session "Supporting semantic search with Core Spotlight" as required background. The iOS 27 semantic index layers semantic search **on top of** the existing keyword index.

---

## 2. Creating the tool

✅ **VERIFIED** (session 246)

```swift
import CoreSpotlight
import FoundationModels

// One line — ready to search your app's Core Spotlight index
let tool = SpotlightSearchTool()

// Or with a custom configuration
let fileTool = SpotlightSearchTool(
    configuration: .init(
        sources: [
            .files
        ]
    )
)
```

The `sources:` array scopes what the tool can reach. `.files` searches file paths in the app's sandbox. 🔴 UNVERIFIED: enumerate the full `sources` case list. **This is where the answer to the privacy question probably lives — see §8.**

## 3. Attaching to a session

✅ **VERIFIED** (session 246)

```swift
let tool = SpotlightSearchTool()

let session = LanguageModelSession(
    model: model,
    tools: [tool],
    instructions: instructions
)

let response = try await session.respond(to: "What hikes have I gone on?")
```

For Memento the equivalent is `"When did I start feeling burnt out?"` — and the whole architecture rests on that returning the right entries.

---

## 4. The index delegate — hydration

✅ **VERIFIED** (session 246)

Critical detail: **some donated metadata is stored compactly and is not readable by the model.** You recover the full item on demand:

```swift
import CoreSpotlight

class IndexDelegate: NSObject, CSSearchableIndexDelegate {

    // Called when the index requests searchable items for the provided identifiers
    func searchableItems(forIdentifiers identifiers: [String]) async -> [CSSearchableItem] {
        let entries = await myStore.fetchEntries(ids: identifiers)
        return entries.map { makeSearchableItem(from: $0) }
    }
}
```

**Memento use:** the compact index will not carry the full transcript. The delegate is where you return the entry text, mood labels, topics, place, and weather so the model can actually reason over them. **Without this, retrieval returns titles and the reflections will be vague and ungrounded.** This is not optional polish; it is the difference between a working product and a plausible-sounding one.

Also implement a **reindex extension** so the system can rebuild the index without launching the app. 🟡 LIKELY (named in Apple's prerequisite session).

---

## 5. Consuming results — the async sequence

✅ **VERIFIED** (session 246)

The session response suits an assistant-style UI. The tool's raw items suit a list UI. You get both.

```swift
let tool = SpotlightSearchTool()

for await reply in tool.searchResults {

    if reply.queryToken != currentToken {
        // New query — start a new display section
        currentToken = reply.queryToken
    }

    switch reply.content {
    case .items(let searchItems):
        // ...
    }
}
```

**`queryToken` matters because the model may call the tool multiple times per response.** Results arrive as batched partial replies. Without tracking the token you will merge two different searches into one list.

### Reply content cases

✅ VERIFIED (session 246):

```swift
for await reply in tool.searchResults {
    let label = reply.label
    switch reply.content {
    case .items(let searchItems):      // raw CSSearchableItems
    case .scoredItems(let scored):     // items with scores from a custom stage
    case .groupedItems(let groups):    // grouped results
    case .count(let count):            // "how many times did I..."
    case .table(let table):            // tabular computed data
    case .statistic(let statistic):    // computed statistic
    case .text(let text):
        continue
    }
}
```

**Memento design opportunity:** `.count`, `.statistic`, and `.table` mean the model can answer *"how many times did I write about my brother this year?"* with a computed number rather than prose that guesses. `reply.label` gives you a display label for the section. This is a much richer UI surface than a chat bubble, and it's exactly where a design-led product should spend effort.

---

## 6. Guidance profiles — critical for on-device

✅ **VERIFIED** (session 246)

`SpotlightSearchTool` exposes its **full** search capability to guided generation by default. That's a large schema, and on a 8192-token on-device context it will crowd out everything else.

```swift
let profile = SpotlightSearchTool.GuidanceProfile(
    textMatch: true,
    dates: true,
    people: false,
    attributes: [.title, .altitude, .completionDate]
)

let tool = SpotlightSearchTool(
    configuration: .init(
        guide: .init(level: .dynamic(profile))
    )
)

// On-device models have smaller context — prefer focused guidance
let focusedTool = SpotlightSearchTool(
    configuration: .init(
        guide: .init(level: .focused(.items))
    )
)
```

Apple's own comment in the sample: **"On-device models have smaller context — prefer focused guidance."** ✅ VERIFIED.

**Memento requirement:** two tool configurations, not one.

| Zone | Guide level | Attributes |
|---|---|---|
| **Z0** (degraded chat, on-device) | `.focused(.items)` | minimal |
| **Z1** (PCC chat, 32K context) | `.dynamic(profile)` | `textMatch: true`, `dates: true`, `people: true`, plus mood/topic/place attributes |

`dates: true` is essential for Memento — nearly every meaningful journal question is temporal ("when did I start...", "how was March compared to...").

---

## 7. ContactResolver — "who did I write about?"

✅ **VERIFIED** (session 246)

```swift
struct MementoContactResolver: ContactResolver {
    func userIdentity() -> ResolvedContact {
        var contact = ResolvedContact(displayName: "Jane Doe")
        contact.emailAddresses = ["jane@example.com"]
        contact.names = ["Jane", "JD"]
        return contact
    }
}

tool.contactResolver = MementoContactResolver()
```

Purpose: when a query references a person ("Who did I go hiking with?"), the resolver disambiguates and filters.

**Memento caution.** The obvious implementation pulls from the Contacts framework. **Do not.** Requesting contacts access in a private journal is an unforced privacy and trust cost, and it introduces data Memento has no business holding. Resolve identity from the user's own Sign in with Apple profile only — enough to distinguish "I" and "me" from other names in entries. If richer person-resolution is wanted later, it should come from names the user has themselves written in entries, not from their address book.

---

## 8. 🔴 THE BLOCKING QUESTION — system search visibility

**This is DEC-002 in the architecture spec and it is P0.**

Core Spotlight is a *system* index. If Memento donates journal text to `CSSearchableIndex.default()`, that text may surface in system-wide Spotlight search. Someone picks up an unlocked iPhone, types a word, and reads a private journal line. For this product that is category-ending.

### Leading hypothesis — test this first

`CSSearchableIndex` supports **named indexes** as well as the default one:

```swift
// System-visible
CSSearchableIndex.default()

// Named / app-private — DOES SpotlightSearchTool reach this?
CSSearchableIndex(name: "memento-entries")
```

🔴 **UNVERIFIED.** The hypothesis is that a named index is app-scoped and does not feed system Spotlight UI, while remaining queryable by the owning app. If `SpotlightSearchTool` can be configured to search a named index, the entire problem dissolves. The `configuration: .init(sources: [...])` parameter is the likely mechanism.

### Investigation order

1. Enumerate `SpotlightSearchTool.Configuration.sources` cases in the SDK. Does one target a named/private index?
2. Donate to `CSSearchableIndex(name:)` and confirm items do **not** appear in system Spotlight on-device.
3. Confirm `SpotlightSearchTool` can still retrieve them.
4. Check whether Data Protection class on the index gates availability while the device is locked.
5. Check `CSSearchableItemAttributeSet` for any exclude-from-system-UI attribute.

### If it resolves negatively

Two fallbacks, in order of preference:

**Fallback A — opt-in indexing.** Default `excludedFromIndex = true`. Present indexing as explicit opt-in with a plain-language tradeoff explanation. Accept degraded retrieval for users who decline.

**Fallback B — hand-rolled retrieval tool.** Write a custom `Tool` conforming to the Foundation Models tool protocol that queries SwiftData directly: date-range predicates, `NLTagger`-derived keyword matching, mood/topic filters, returning top-N entries as structured tool output. Materially weaker than semantic retrieval, but keeps the architecture serverless and keeps journal text out of any system index.

Fallback B must be **specified** in `/specs/indexing-retrieval.spec.md` even if unbuilt, with an explicit trigger condition.

---

## 9. Custom pipeline stages

✅ **VERIFIED** (session 246). New in iOS 27, and a strong fit for Memento.

For complex requests, the model can run a **pipeline of search plus computation stages** rather than a simple query. You register your own `@Generable` stages; the model generates them on demand and may return computed data back to the app for display.

```swift
@Generable
struct HappinessStage: CustomStage {
    static var name = "happiness"
    static var description = "Scores hike by how happy the author was"
    static var inputTypes: [SearchPipelineDataType] = [.items]
    static var outputTypes: [SearchPipelineDataType] = [.scoredItems]

    @Guide(description: "Minimum happiness score (0.0-1.0) to include in results")
    var threshold: Double?

    func execute(on input: SearchPipelineData) async throws -> SearchPipelineData {
        return SearchPipelineData(payload: .scoredItems(sorted))
    }
}

let tool = SpotlightSearchTool(configuration: .init(
    customStages: [.happinessBoost(threshold: 0.5)]
))
```

### Memento stages worth building

| Stage | Input → Output | Answers |
|---|---|---|
| `MoodValenceStage` | `.items` → `.scoredItems` | "show me the hardest weeks this year" |
| `SalienceStage` | `.items` → `.scoredItems` | "what mattered most in March" |
| `RecurrenceStage` | `.items` → `.groupedItems` | "what do I keep coming back to" |
| `CadenceStage` | `.items` → `.statistic` | "how often did I write when I was anxious" |

This is a significant capability. It moves computation *into* the retrieval loop rather than making the LLM approximate arithmetic over prose — which is exactly where journaling apps produce confidently wrong pattern claims. Prefer a stage over asking the model to count.

---

## 10. Donation requirements for Memento

Every `Entry` where `excludedFromIndex == false`:

- `CSSearchableItemAttributeSet` carrying: full transcript as textual content, title, `contentCreationDate`, mood labels, topics, place name
- Conform `Entry` to App Intents' `IndexedEntity` so one donation serves Siri, Spotlight actions, and the search tool (see `07-app-intents-and-surfaces.md`)
- Implement `CSSearchableIndexDelegate.searchableItems(forIdentifiers:)` for hydration (§4)
- Implement a reindex extension
- Incremental donation on save and delete
- A **full reindex path**, triggerable from Settings ("Rebuild search index"), for support purposes
- On "delete everything," Spotlight entries MUST be removed. Leaving them behind is a P0 privacy defect.

**Metadata quality directly determines retrieval quality.** Session 246 makes this point explicitly. Sparse attribute sets produce vague answers. Spend the effort here.

---

## 11. Quality gate

Before any generative surface depending on retrieval ships:

- Fixture corpus: **≥ 250 entries spanning ≥ 8 months**
- Question set: **≥ 40 hand-authored queries with known correct entries**
- Pass condition: **recall@5 ≥ 0.85**

Retrieval failure is invisible to users but poisons every downstream surface. Use the Evaluations framework to automate this — see `04-evaluations.md`, which includes Apple's own worked example of exactly this test.

---

## 12. Related note — iOS 27 index rebuild

Apple rearchitected the search index in iOS 27. On update, devices reindex existing content, which users see as an "Indexing in Progress" banner that can persist for days on large libraries. New content becomes searchable "almost immediately" once caught up.

**Implication:** on a fresh iOS 27 device or right after update, Memento's retrieval may be degraded while system indexing completes. Detect and communicate this rather than letting the Ask surface silently return nothing. 🔴 UNVERIFIED whether an API exposes index-readiness state — investigate.
