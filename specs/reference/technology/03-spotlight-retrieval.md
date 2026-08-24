# Core Spotlight + SpotlightSearchTool — the retrieval layer

**Imports:** `import CoreSpotlight`, `import FoundationModels`
**Module note (✅ verified against iOS 27.0 SDK, Xcode 27 beta 4 / 27A5228h, 2026-07-25):** `SpotlightSearchTool` and its supporting types live in the `_CoreSpotlight_FoundationModels` **cross-import overlay** — it is not declared in either parent framework's own interface. Importing both `CoreSpotlight` and `FoundationModels` loads it automatically; no third import is written in source.
**Availability:** `SpotlightSearchTool` — iOS 27, iPadOS 27, macOS 27, visionOS 27. ✅ VERIFIED in SDK: `@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)`, `@available(tvOS, unavailable)`, `@available(watchOS, unavailable)`. **Note: not watchOS (and not tvOS).**
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

The `sources:` array scopes what the tool can reach. `.files` searches file paths in the app's sandbox.

✅ **V9 RESOLVED — full `sources` surface enumerated** (verified against iOS 27.0 SDK (27A5228h), 2026-07-25). `SearchSource` is a struct (not an enum) exposing exactly **two source families**, each in bare and configured form:

```swift
public struct SearchSource : Sendable {
  public static var coreSpotlight: SearchSource { get }
  public static func coreSpotlight(_ source: CoreSpotlightSource) -> SearchSource
  public static var files: SearchSource { get }
  public static func files(_ source: FileSource) -> SearchSource
}

public struct CoreSpotlightSource : @unchecked Sendable {
  public var fetchAttributes: [SearchableItemAttribute]
  public var maximumResultCount: Int?
  public var searchableIndexDelegate: (any CSSearchableIndexDelegate)?
  public init(searchableIndexDelegate: (any CSSearchableIndexDelegate)? = nil,
              fetchAttributes: [SearchableItemAttribute] = [])
  public init(fetchAttributes: [SearchableItemAttribute] = [])
}

public struct FileSource : Sendable {
  public var fetchAttributes: [SearchableItemAttribute]
  public var maximumResultCount: Int?
  public var scopes: [URL]
  public init(fetchAttributes: [SearchableItemAttribute] = [])
}
```

The tool's default init is `init(configuration: Configuration = Configuration(sources: [.coreSpotlight]))`, and the full `Configuration` surface is:

```swift
public struct Configuration : Sendable {
  public var sources: [SearchSource]
  public var guide: SpotlightSearchTool.Guide?
  public var contactResolver: (any ContactResolver)?
  public var customStages: [any CustomStage] { get set }
  public var maximumResponseSize: Int?
  public init(sources: [SearchSource] = [], guide: SpotlightSearchTool.Guide? = nil,
              contactResolver: (any ContactResolver)? = nil,
              customStages: [any CustomStage] = [], maximumResponseSize: Int? = nil)
}
```

~~This is where the answer to the privacy question probably lives — see §8.~~ **Superseded — it does not.** `CoreSpotlightSource` has **no parameter to select an index** — no index name, no `CSSearchableIndex` instance, no protection-class scope. There is no third "named/private index" source. The §8 hypothesis that `sources:` can point the tool at a named index is **not supported by the public API surface**; see §8 for the fuller finding. Note the useful positive: `CoreSpotlightSource.searchableIndexDelegate` is where the §4 hydration delegate is wired into the tool.

## 3. Attaching to a session

✅ **VERIFIED** (session 246; registration form ✅ V10 RESOLVED against iOS 27.0 SDK (27A5228h), 2026-07-25)

```swift
let tool = SpotlightSearchTool()

let session = LanguageModelSession(
    model: model,
    tools: [tool],
    instructions: instructions
)

let response = try await session.respond(to: "What hikes have I gone on?")
```

**Registration is instance-based — `tools: [tool]`, not `tools: [MyTool.self]`.** Every `LanguageModelSession` initializer in the SDK takes `tools: [any Tool] = []`; no metatype overload exists:

```swift
convenience public init(model: SystemLanguageModel = .default, tools: [any Tool] = [],
                        instructions: Instructions? = nil)
// (same `tools: [any Tool] = []` on the String-instructions, @InstructionsBuilder,
//  transcript, and `model: some LanguageModel` variants)
```

**Related (V11, confirmed in FoundationModels):** `GenerationOptions.toolCallingMode: ToolCallingMode?` exists, iOS 27.0+, with static values `.allowed`, `.required`, `.disallowed`. For the Ask surface, `.required` is the "always search, never answer from world knowledge" setting:

```swift
public struct ToolCallingMode : Sendable, Equatable {
  public var kind: Kind        // enum Kind { case allowed, required, disallowed }
  public static let allowed: ToolCallingMode
  public static let required: ToolCallingMode
  public static let disallowed: ToolCallingMode
}
public init(samplingMode: GenerationOptions.SamplingMode? = nil, temperature: Double? = nil,
            maximumResponseTokens: Int? = nil, toolCallingMode: GenerationOptions.ToolCallingMode?)
```

For Memento the equivalent is `"When did I start feeling burnt out?"` — and the whole architecture rests on that returning the right entries.

---

## 4. The index delegate — hydration

✅ **VERIFIED** (session 246; signature re-confirmed against iOS 27.0 SDK (27A5228h), 2026-07-25)

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

✅ **§16-item-3 re-confirmed in the iOS 27.0 SDK.** The ObjC protocol methods (`CSSearchableIndex.h`) that surface in Swift as `searchableItems(forIdentifiers:) async -> [CSSearchableItem]` are still present, plus a **new iOS 27 protection-class overload**:

```objc
// iOS 18.4+ — Swift: func searchableItems(forIdentifiers:) async -> [CSSearchableItem]
- (void)searchableItemsForIdentifiers:(NSArray<NSString *> *)identifiers
               searchableItemsHandler:(void (^)(NSArray<CSSearchableItem *> *items))searchableItemsHandler
    NS_SWIFT_ASYNC(2);

// NEW iOS 27.0 — Swift: func searchableItems(forIdentifiers:protectionClass:) async -> [CSSearchableItem]
- (void)searchableItemsForIdentifiers:(NSArray<NSString *> *)identifiers
                      protectionClass:(NSFileProtectionType)protectionClass
               searchableItemsHandler:(void (^)(NSArray<CSSearchableItem *> *items))searchableItemsHandler
    NS_SWIFT_ASYNC(3);
```

**Wiring detail (new finding):** the delegate reaches `SpotlightSearchTool` through `CoreSpotlightSource(searchableIndexDelegate:fetchAttributes:)` — i.e. it is attached per-source in the tool configuration, in addition to the classic `CSSearchableIndex.indexDelegate` path.

**Memento use:** the compact index will not carry the full transcript. The delegate is where you return the entry text, mood labels, topics, place, and weather so the model can actually reason over them. **Without this, retrieval returns titles and the reflections will be vague and ungrounded.** This is not optional polish; it is the difference between a working product and a plausible-sounding one.

Also implement a **reindex extension** so the system can rebuild the index without launching the app. ✅ VERIFIED — `CSIndexExtensionRequestHandler.h` is present in the iOS 27.0 SDK, and the reindex entry points are the `@required` `CSSearchableIndexDelegate` methods `searchableIndex(_:reindexAllSearchableItemsWithAcknowledgementHandler:)` and `searchableIndex(_:reindexSearchableItemsWithIdentifiers:acknowledgementHandler:)`.

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

✅ VERIFIED — full case list confirmed against iOS 27.0 SDK (27A5228h), 2026-07-25. The seven-case list from session 246 is correct, but the **payload types are richer than the sample implied**: `.count`, `.statistic`, and `.text` carry small structs (with an optional `header`), not bare scalars. Exact declaration:

```swift
public struct SearchReply : Sendable {
  public enum Content : @unchecked Sendable {
    case items([SearchableItem])                                       // SearchableItem wraps CSSearchableItem
    case groupedItems([SearchableItemAttribute : [SearchableItem]])
    case scoredItems([ScoredSearchableItem])                           // { item: SearchableItem, score: Double }
    case count(SearchCount)                                            // { value: Int, header: String? }
    case table(SearchResultsTable)                                     // { header: String?, columns:, rows: }
    case statistic(SearchStatistic)                                    // { name: String, value: Double, header: String? }
    case text(SearchTextResult)                                        // { body: String, header: String? }
  }
  public let content: Content
  public let label: String?
  public let queryToken: QueryToken      // Sendable, Hashable
  public let stageToken: StageToken      // Sendable, Hashable — NEW vs. the session sample
  public let status: Status              // enum Status { case partial, complete }
}
```

and `searchResults` itself:

```swift
public var searchResults: some AsyncSequence<SpotlightSearchTool.SearchReply, Never> { get }
```

Two additions not in the session-246 sample: **`stageToken`** identifies which pipeline stage (§9) produced a partial reply, and **`status`** (`.partial`/`.complete`) makes end-of-query explicit — the consumption loop should key sections on `queryToken` and close them on `.complete` rather than inferring completion.

**Memento design opportunity:** `.count`, `.statistic`, and `.table` mean the model can answer *"how many times did I write about my brother this year?"* with a computed number rather than prose that guesses. `reply.label` gives you a display label for the section. This is a much richer UI surface than a chat bubble, and it's exactly where a design-led product should spend effort.

---

## 6. Guidance profiles — critical for on-device

✅ **VERIFIED** (session 246; exact declarations confirmed against iOS 27.0 SDK (27A5228h), 2026-07-25)

```swift
public struct Guide : Sendable {
  public let level: GuidanceLevel
  public let format: FormatLevel
  public init(level: GuidanceLevel = .complete, format: FormatLevel = .structured)
  public static var complete: Guide { get }
  public static func focused(_ domain: ContentDomain = .items) -> Guide
  public static func dynamic(_ profile: GuidanceProfile) -> Guide
}
public enum GuidanceLevel : Sendable { case complete; case focused(_: ContentDomain = .items); case dynamic(GuidanceProfile) }
public enum FormatLevel : Sendable { case structured, compact }

public struct GuidanceProfile : Sendable {
  public var textMatch: Bool?
  public var similarityMatch: Bool?    // not in the session sample
  public var numericMatch: Bool?       // not in the session sample
  public var dates: Bool?
  public var people: Bool?
  public var contentType: Bool?        // not in the session sample
  public var attributes: [SearchableItemAttribute]?
  public init(textMatch: Bool? = nil, similarityMatch: Bool? = nil, numericMatch: Bool? = nil,
              dates: Bool? = nil, people: Bool? = nil, contentType: Bool? = nil,
              attributes: [SearchableItemAttribute]? = nil)
}
```

Notes: the sample's `GuidanceProfile(textMatch:dates:people:attributes:)` call compiles because every parameter is defaulted — the full profile also has `similarityMatch`, `numericMatch`, and `contentType` (relevant to Z1: `similarityMatch: true` is presumably the semantic-search switch). `Guide` also carries a `format:` level (`.structured`/`.compact`) the session never mentioned. `SearchableItemAttribute` is a `RawRepresentable` String struct, and the sample's `.title`, `.altitude`, `.completionDate` (plus `.textContent`, `.contentCreationDate`, etc.) all exist as static members. `ContentDomain` offers `.items`, `.audio`, `.calendar`, `.communications`, `.documents`, `.visualMedia`, each with a configurable variant (e.g. `.items(Items(title:text:created:modified:))`) — Memento wants `.items`.

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

✅ **VERIFIED** (session 246; protocol confirmed against iOS 27.0 SDK (27A5228h), 2026-07-25) — with one wiring correction:

```swift
public protocol ContactResolver : Sendable {
  func userIdentity() -> ResolvedContact
}
public struct ResolvedContact : Sendable {
  public var displayName: String
  public var names: [String]
  public var nameComponents: [PersonNameComponents]
  public var emailAddresses: [String]
  public var phoneNumbers: [String]
  public init(displayName: String)
}

struct MementoContactResolver: ContactResolver {
    func userIdentity() -> ResolvedContact {
        var contact = ResolvedContact(displayName: "Jane Doe")
        contact.emailAddresses = ["jane@example.com"]
        contact.names = ["Jane", "JD"]
        return contact
    }
}
```

~~`tool.contactResolver = MementoContactResolver()`~~ **DIFFERS from the session sample:** there is no settable `contactResolver` on the tool — `SpotlightSearchTool.configuration` is a `let`, so the resolver must be supplied at construction via `Configuration(contactResolver:)`:

```swift
let tool = SpotlightSearchTool(configuration: .init(contactResolver: MementoContactResolver()))
```

Purpose: when a query references a person ("Who did I go hiking with?"), the resolver disambiguates and filters.

**Memento caution.** The obvious implementation pulls from the Contacts framework. **Do not.** Requesting contacts access in a private journal is an unforced privacy and trust cost, and it introduces data Memento has no business holding. Resolve identity from the user's own Sign in with Apple profile only — enough to distinguish "I" and "me" from other names in entries. If richer person-resolution is wanted later, it should come from names the user has themselves written in entries, not from their address book.

---

## 8. 🔴 THE BLOCKING QUESTION — system search visibility

**This is DEC-002 in the architecture spec and it is P0.**

Core Spotlight is a *system* index. If Memento donates journal text to `CSSearchableIndex.default()`, that text may surface in system-wide Spotlight search. Someone picks up an unlocked device, types a word, and reads a private journal line. For this product that is category-ending. Inbound CloudKit rows must be re-donated locally — Spotlight does not replicate (spec 016 / 040).

### Leading hypothesis — test this first

`CSSearchableIndex` supports **named indexes** as well as the default one:

```swift
// System-visible
CSSearchableIndex.default()

// Named / app-private — DOES SpotlightSearchTool reach this?
CSSearchableIndex(name: "memento-entries")
```

🟡 **PARTIALLY RESOLVED — SDK surface swept; behavioral test still required** (verified against iOS 27.0 SDK (27A5228h), 2026-07-25).

**What the SDK confirms (for spec 013 R1 Spike C) — exact initializers from `CSSearchableIndex.h`:**

```objc
+ (BOOL)isIndexingAvailable;
+ (instancetype)defaultSearchableIndex;
- (instancetype)initWithName:(NSString *)name;                    // Swift: CSSearchableIndex(name:)
- (instancetype)initWithName:(NSString *)name
              protectionClass:(nullable NSFileProtectionType)protectionClass;
                                                                  // Swift: CSSearchableIndex(name:protectionClass:)
// protectionClass must be NSFileProtectionComplete, .CompleteUnlessOpen,
// or .CompleteUntilFirstUserAuthentication (header comment)

// NEW in iOS 27.0:
@property (nonatomic, readonly) NSFileProtectionType protectionClass;
```

iOS 27 also adds a `CSSearchableIndexDescription` class (`NSSecureCoding`/`NSCopying`) whose only public member is a readonly `protectionClass`.

**What the SDK refutes:** ~~The `configuration: .init(sources: [...])` parameter is the likely mechanism.~~ It is not. §2's enumeration shows `sources` has exactly two families (`.coreSpotlight`, `.files`) and `CoreSpotlightSource` carries **no index name, no `CSSearchableIndex` instance, and no protection-class parameter** — there is no public way to point `SpotlightSearchTool` at a specific named index. Worse for the hypothesis, the header's own comment on `initWithName:` describes the name as *"a handle for the client state used with the batch API"* — i.e. named indexes exist for client-state batching, **not** documented as a privacy/visibility scope. Also checked: no exclude-from-system-UI attribute exists anywhere in the `CSSearchableItemAttributeSet*` headers (investigation item 5: negative). Query-side only, `CSUserQuery.disableSemanticSearch` (iOS 18+) exists but does not affect donation visibility.

**What remains genuinely open (on-device behavioral questions the API surface cannot answer):** whether items donated to a named index appear in system Spotlight UI, and whether `SpotlightSearchTool`'s `.coreSpotlight` source reads them. If named-index items are both hidden from system UI *and* reachable by the tool (which searches the app's Core Spotlight data as a whole), the problem still dissolves — but nothing in the public surface promises this either way.

### Investigation order (updated)

1. ~~Enumerate `SpotlightSearchTool.Configuration.sources` cases in the SDK. Does one target a named/private index?~~ ✅ Done — no, it cannot (see above).
2. Donate to `CSSearchableIndex(name:)` and confirm items do **not** appear in system Spotlight on-device.
3. Confirm `SpotlightSearchTool` can still retrieve them.
4. Check whether Data Protection class on the index gates availability while the device is locked — `CSSearchableIndex(name:protectionClass:)` and the new readonly `protectionClass` property are the levers.
5. ~~Check `CSSearchableItemAttributeSet` for any exclude-from-system-UI attribute.~~ ✅ Done — none exists in the iOS 27.0 SDK headers.

### If it resolves negatively

Two fallbacks, in order of preference:

**Fallback A — opt-in indexing.** Default `excludedFromIndex = true`. Present indexing as explicit opt-in with a plain-language tradeoff explanation. Accept degraded retrieval for users who decline.

**Fallback B — hand-rolled retrieval tool.** Write a custom `Tool` conforming to the Foundation Models tool protocol that queries SwiftData directly: date-range predicates, `NLTagger`-derived keyword matching, mood/topic filters, returning top-N entries as structured tool output. Materially weaker than semantic retrieval, but keeps the architecture serverless and keeps journal text out of any system index.

Fallback B must be **specified** in `/specs/indexing-retrieval.spec.md` even if unbuilt, with an explicit trigger condition.

---

## 9. Custom pipeline stages

✅ **VERIFIED** (session 246), with the protocol shape corrected against the iOS 27.0 SDK (27A5228h), 2026-07-25. New in iOS 27, and a strong fit for Memento.

For complex requests, the model can run a **pipeline of search plus computation stages** rather than a simple query. You register your own `@Generable` stages; the model generates them on demand and may return computed data back to the app for display.

**DIFFERS from the session sample:** there is no `execute(on input: SearchPipelineData)` requirement. The real protocol declares **typed `execute` overloads per input kind**, every one of which has a default implementation — you implement only the overloads matching your declared `inputTypes`:

```swift
public protocol CustomStage : Generable, Decodable, Encodable, Sendable {
  static var name: String { get }          // "The stage type name as it appears in the pipeline"
  static var description: String { get }
  static var inputTypes: [SearchPipelineDataType] { get }
  static var outputTypes: [SearchPipelineDataType] { get }
  func execute(items: [SearchableItem]) async throws -> SearchPipelineData
  func execute(scoredItems: [ScoredSearchableItem]) async throws -> SearchPipelineData
  func execute(groupedItems: [SearchableItemAttribute : [SearchableItem]]) async throws -> SearchPipelineData
  func execute(count: Int) async throws -> SearchPipelineData
  func execute(table: SearchResultsTable) async throws -> SearchPipelineData
  func execute(statisticName: String, value: Double) async throws -> SearchPipelineData
  func execute(text: String) async throws -> SearchPipelineData
}

public enum SearchPipelineDataType : String, Codable, CaseIterable, Sendable {
  case items, scoredItems, groupedItems, count, table, statistic, text
}

public struct SearchPipelineData : Sendable {
  public let payload: Payload
  public init(payload: Payload)
  // enum Payload mirrors the seven cases; static conveniences exist:
  // .items(_:), .scoredItems(_:), .groupedItems(_:), .count(_:), .table(_:),
  // .statistic(name:value:), .text(_:)
}
```

Registration takes **instances** — `customStages: [any CustomStage]` on `Configuration`. The sample's `.happinessBoost(threshold: 0.5)` was a sample-local static convenience, not SDK API; write `customStages: [HappinessStage()]` (or your own static helpers).

```swift
@Generable
struct HappinessStage: CustomStage {
    static var name = "happiness"
    static var description = "Scores hike by how happy the author was"
    static var inputTypes: [SearchPipelineDataType] = [.items]
    static var outputTypes: [SearchPipelineDataType] = [.scoredItems]

    @Guide(description: "Minimum happiness score (0.0-1.0) to include in results")
    var threshold: Double?

    func execute(items: [SearchableItem]) async throws -> SearchPipelineData {
        return .scoredItems(sorted)
    }
}

let tool = SpotlightSearchTool(configuration: .init(customStages: [HappinessStage()]))
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

**Implication:** on a fresh iOS 27 device or right after update, Memento's retrieval may be degraded while system indexing completes. Detect and communicate this rather than letting the Ask surface silently return nothing.

✅ **V26 RESOLVED — NEGATIVE** (verified against iOS 27.0 SDK (27A5228h), 2026-07-25). **No index-readiness / catch-up API exists in CoreSpotlight's public surface.** Swept the full `CoreSpotlight.swiftmodule` interface and every header (`CSSearchableIndex.h`, `CSUserQuery.h`, `CSSearchQuery.h`, etc.) for readiness/progress/state APIs — nothing queryable for "has indexing caught up". The closest surfaces, none of which answer the question:

- `CSSearchableIndex.isIndexingAvailable` — device *capability* check only, not catch-up state
- `CSIndexErrorCode.indexUnavailableError` (-1000) / `.indexingUnsupported` (-1005) — error codes, reactive only
- `CSSearchableIndexDelegate` optional callbacks `searchableIndexDidThrottle(_:)` / `searchableIndexDidFinishThrottle(_:)` — battery throttling notice, not rebuild progress
- `CSUserQuery.prepare()` / `prepareProtectionClasses(_:)` (iOS 18+) — warms query resources, returns nothing
- `fetchLastClientStateWithCompletionHandler:` — the app's *own* batching state, not the system's indexing progress

**Consequence for spec 016 R9:** the degraded-retrieval state must be entered on a **heuristic** (e.g. post-OS-update window + anomalously empty results), labeled as such in the design. There is no signal to subscribe to.
