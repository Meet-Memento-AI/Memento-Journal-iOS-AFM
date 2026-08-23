# Memento 2.0 — Architecture Specification

**Document type:** Spec-Driven Development source of truth
**Supersedes:** Memento 1.3 architecture (Supabase + pgvector + Gemini)
**Target platform:** iOS 27 / iPadOS 27 / watchOS 27
**Status:** Draft for spec derivation
**Last revised:** July 2026

---

## 0. How to use this document

This is the **root artifact** in a spec-driven-development chain. It is deliberately more detailed than a PRD and more opinionated than an RFC. Nothing below is implementation; everything below is contract.

**Derivation order:**

```
memento-2.0-architecture-spec.md   ← you are here (WHAT and WHY)
   ├── /specs/data-layer.spec.md
   ├── /specs/indexing-retrieval.spec.md
   ├── /specs/intelligence.spec.md
   ├── /specs/capture.spec.md
   ├── /specs/voice-output.spec.md
   ├── /specs/surfaces/*.spec.md
   ├── /specs/system-integration.spec.md
   ├── /specs/privacy-model.spec.md
   └── /specs/monetization.spec.md
          ↓
      /plans/*.plan.md   (task decomposition)
          ↓
      implementation
```

**Conventions used throughout:**

| Marker | Meaning |
|---|---|
| `REQ-XXX-nnn` | Normative requirement. Must appear in a derived spec with acceptance criteria. |
| `DEC-nnn` | Open decision. Must be resolved before the dependent spec is written. Blocking. |
| `⚠️ VERIFY` | Claim based on WWDC26 session material or pre-GA documentation. Confirm against the current beta SDK before writing the derived spec. |
| `NON-GOAL` | Explicitly out of scope. Do not let a coding agent helpfully add it. |

**MUST / SHOULD / MAY** carry RFC 2119 meanings.

When generating a derived spec from this document, the prompt should be: *"Using `memento-2.0-architecture-spec.md` §N as the normative source, produce `/specs/<name>.spec.md` containing: interface contracts, data shapes, state machines, error taxonomy, acceptance criteria in Given/When/Then form, and an explicit list of every `⚠️ VERIFY` item that must be confirmed before implementation begins. Do not invent requirements not traceable to a REQ- identifier."*

---

## 1. Product definition

### 1.1 One sentence

Memento is a voice-first journal that remembers what you said, notices what repeats, answers questions about your own history, and reads its reflections back to you in your own voice — without your words leaving Apple's trust boundary.

### 1.2 What changed and why

Memento 1.3 was architected in 2025 around the assumption that meaningful RAG over personal text requires server infrastructure: a Postgres instance with pgvector, an embeddings pipeline, and a hosted LLM. That assumption held until 8 June 2026.

Three WWDC26 changes invalidated it:

1. **`SpotlightSearchTool`** — the Foundation Models framework ships a built-in tool that lets a language model author its own queries against an app's Core Spotlight semantic index and reason over the results. Local RAG with no embedding pipeline, no vector store, no retrieval endpoint.
2. **Foundation Models on Private Cloud Compute** — a server-class model reachable with no account, no authentication, no API key, and no token cost to the developer, subject to a daily per-user limit that rises for iCloud+ subscribers, available to apps under 2M first-time downloads whose developers are enrolled in the App Store Small Business Program.
3. **The `LanguageModel` protocol** — the session API now fronts a *model slot* rather than a single model. On-device, PCC, Claude, Gemini, and local open-weights models are all reachable through one API, and swapping between them is an argument change rather than a rewrite.

The consequence is that Memento's entire server tier is now **cost without differentiation**. Every capability it provided is available for free, better integrated, with a stronger and more legible privacy story, and with lower latency for the majority of calls.

### 1.3 Competitive position

The reference competitor is **Slate** (HSLA0001 Inc., July 2026): fully on-device, 2.9 MB, iOS 26+, $7.99/mo or $59.99/yr, "Data Not Collected" privacy label, optional encrypted iCloud backup. Slate's product doctrine is explicit and self-limiting: *the model observes, never replies, never advises, never chats.* Weekly Sunday summary only. No streaks, no scores, no chat.

Memento does not compete on privacy absolutism — that position is taken, and taking it second is losing. Memento competes on **the ground Slate's doctrine vacates**:

| Axis | Slate | Rosebud / Day One / Reflectly | Memento 2.0 |
|---|---|---|---|
| Data leaves device | Never | Yes, to vendor clouds | Never to a third party; optionally to Apple PCC, user-visible |
| Conversational recall | Refused by design | Yes, but on a vendor's servers | Yes, inside Apple's trust boundary |
| Reads back aloud | No | No | Yes, optionally in the user's own voice |
| System integration | Minimal | Minimal | Deep (Spotlight, Siri, Health, Journaling Suggestions, Watch) |
| Emotional register | Austere, cold by design | Coach-y, performative | Warm, specific, restrained |

**Positioning claim (must be defensible verbatim):**
> No account. No analytics. No third-party AI. Your words are processed on your iPhone, or on Apple's Private Cloud Compute, which stores nothing and is independently verifiable. Nothing else.

**REQ-POS-001** — Marketing, App Store copy, and in-app text MUST NOT claim "nothing leaves your phone," "no network calls," or "airplane mode proves it" while PCC routing is enabled for any surface. Overstating the trust boundary is an existential brand risk and is treated as a P0 defect.

### 1.4 Non-goals

- **NON-GOAL:** Android, web, or any non-Apple client.
- **NON-GOAL:** Any developer-operated server, database, or API endpoint holding user content.
- **NON-GOAL:** Social features, sharing, streaks, scores, gamification, or notification-driven engagement loops.
- **NON-GOAL:** Therapeutic advice, diagnosis, crisis intervention, or any framing of the app as mental health treatment.
- **NON-GOAL:** Custom model weights or fine-tuning in v2.0 (Core AI remains an escape hatch, §6.7).

---

## 2. Architectural principles

These are the constraints that resolve disputes when requirements conflict.

**P1 — Apple-native by default.**
If Apple ships a framework that does the job, use it. Every third-party dependency must justify its binary weight, its privacy surface, and its presence in the "no third-party SDK" story. The current allowlist is in §12.4 and is short.

**P2 — The device is the system of record.**
SwiftData on-device is authoritative. CloudKit is a replication and durability mechanism, not a backend. Live writes go through SwiftData (spec 040); the user's private DB is the iPhone↔iPad replica. There is no Memento account and no server-side representation of any journal entry, at rest, anywhere, ever. Do not claim the journal is 100% on-device while CloudKit mirroring is enabled.

**P3 — One intelligence boundary.**
Exactly one module imports `FoundationModels`. Every AI surface calls a protocol. Model choice, routing, quota, degradation, and telemetry-free instrumentation all live in one place. This is what makes provider swapping a config change.

**P4 — The trust boundary is a UI element, not a policy page.**
Users must be able to see, at the moment of use, whether a given operation runs on-device or on PCC. Legibility is the product.

**P5 — Degrade visibly, never silently.**
When a capable path is unavailable, the user is told what changed and what they got instead. A quietly worse answer is worse than a clearly labeled simpler one.

**P6 — Speakable by construction.**
Every generated artifact intended for a human to read is also intended for a human to *hear*. Prompts, output schemas, and layout all assume audio rendering. Retrofitting this is a rewrite.

**P7 — Delete before you add.**
The 2.0 work is majority subtraction. Any proposal that reintroduces a service tier must first demonstrate that the Apple-native path was measured and failed.

---

## 3. System overview

### 3.1 Layer diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  SURFACES (SwiftUI, Liquid Glass)                                │
│  Capture · Entry · Timeline · Reflection · Patterns · Ask · Read  │
└───────────────┬──────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────────┐
│  SYSTEM INTEGRATION                                              │
│  App Intents · Siri · Widgets · Controls · Live Activities ·     │
│  Shortcuts · Watch · Journaling Suggestions · Health · Focus     │
└───────────────┬──────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────────┐
│  INTELLIGENCE BOUNDARY  (the only FoundationModels importer)     │
│  IntelligenceService · ModelRouter · QuotaGovernor ·             │
│  PromptRegistry · GenerationContracts (@Generable)               │
└───┬───────────────────────┬──────────────────────┬───────────────┘
    │                       │                      │
┌───▼─────────┐   ┌─────────▼──────────┐   ┌───────▼─────────────┐
│ RETRIEVAL   │   │ CAPTURE            │   │ VOICE OUT           │
│ Core        │   │ SpeechAnalyzer     │   │ AVSpeechSynthesizer │
│ Spotlight   │   │ SpeechTranscriber  │   │ Personal Voice      │
│ +Search Tool│   │ AVAudioEngine      │   │ AVAudioSession      │
└───┬─────────┘   └─────────┬──────────┘   └───────┬─────────────┘
    │                       │                      │
┌───▼───────────────────────▼──────────────────────▼───────────────┐
│  DATA LAYER                                                      │
│  SwiftData (authoritative) ─ CloudKit private DB (replication)   │
│  Data Protection · Keychain · LocalAuthentication                │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 The trust boundary, precisely

Three concentric zones. Every operation in this document is tagged with the innermost zone it requires.

| Zone | Definition | What runs here |
|---|---|---|
| **Z0 — Device** | Never leaves this device. Works in airplane mode. | Transcription, entry reflection, mood inference, tagging, retrieval, search, TTS, all rendering. PIN, audio, embeddings, and Spotlight stay per-device. |
| **Z1 — Apple** | Leaves the device, stays inside Apple's attested infrastructure. Not retained. | PCC generation (weekly, monthly, chat), CloudKit replication (encrypted, user's own account) |
| **Z2 — Third party** | Leaves Apple. | **Nothing.** RevenueCat receives purchase receipts and an anonymous ID only — never content. |

**REQ-PRIV-001** — No journal content, transcript, derived reflection, embedding, tag, mood value, or metadata derived from user content MAY cross into Z2 under any configuration.

**REQ-PRIV-002** — Every generation surface MUST declare its zone in code (an enum on the request) and MUST render that zone in the UI at the point of use.

---

## 4. Platform baseline

**REQ-PLAT-001** — Minimum deployment target: **iOS 27.0**. Justification: `SpotlightSearchTool`, PCC access, and AFM 3 are all iOS 27 features, and they are the architecture. A dual-baseline build supporting iOS 26 would require maintaining a vector store and a separate generation path — precisely the cost this rebuild exists to eliminate.

**REQ-PLAT-002** — Swift 6 language mode with strict concurrency checking set to **complete**. All model-facing services are `actor`-isolated or `@MainActor`.

**REQ-PLAT-003** — The app MUST launch, capture, transcribe, index, search, reflect on a single entry, and read aloud with the network fully disabled. Only §7.3 (weekly), §7.4 (monthly), and §7.5 (chat) MAY require connectivity, and each MUST have a Z0 fallback.

### 4.1 Capability matrix

Capability is not uniform across devices. The app MUST behave coherently at every rung.

| Tier | Conditions | Behavior |
|---|---|---|
| **Full** | Apple Intelligence device, iOS 27, PCC eligible, quota available | All surfaces, PCC for heavy synthesis |
| **Local** | Apple Intelligence device, PCC unavailable/capped/disabled by user | All surfaces, on-device generation, labeled |
| **Reduced** | iOS 27, non-Apple-Intelligence device | Capture, transcription, timeline, keyword search, TTS. Generative surfaces disabled with honest explanation. |
| **Blocked** | < iOS 27 | Not installable |

**REQ-PLAT-004** — Tier MUST be resolved at launch and re-resolved on `SystemLanguageModel.availability` change. The paywall MUST NOT be presentable in the Reduced tier without a clearly disclosed feature list. Selling AI reflection to a device that cannot generate it is a refund event and an App Review risk.

**DEC-001** — Does Memento ship at all on Reduced-tier devices, or does it declare an Apple Intelligence device requirement in the App Store listing? Shipping a degraded free tier grows the funnel; declaring a requirement protects the brand. **Blocking for:** monetization spec, App Store listing. **Recommendation:** ship on Reduced tier, but gate it to free-forever capture-only with no paywall presentation.

---

## 5. Data layer

### 5.1 Store configuration

**REQ-DATA-001** — SwiftData with `ModelConfiguration` mirroring to the **CloudKit private database**. No public or shared database. No custom CKRecord schema outside SwiftData's mirroring.

**REQ-DATA-002** — All SwiftData model properties MUST be CloudKit-compatible: optionals or defaulted, no `@Attribute(.unique)` on mirrored entities, all relationships with inverses.

**REQ-DATA-003** — The store file MUST use `NSFileProtectionCompleteUntilFirstUserAuthentication` at minimum; `NSFileProtectionComplete` SHOULD be evaluated against background task requirements (§9.6) and the stricter option chosen if background generation can be scheduled around unlock. ⚠️ VERIFY interaction between `.complete` protection and BGProcessingTask execution while locked.

**REQ-DATA-004** — Optional app lock via `LocalAuthentication` (Face ID / Optic ID / passcode), defaulting **on** for a journaling app. Lock state MUST gate Spotlight result visibility (§6.5).

### 5.2 Entities

```swift
@Model final class Entry {
    var id: UUID
    var createdAt: Date
    var modifiedAt: Date

    // Content
    var transcript: String            // canonical text, whether spoken or typed
    var source: CaptureSource         // .voice, .text, .suggestion
    var audioAssetID: String?         // reference into audio store, §5.4
    var durationSeconds: Double?
    var language: Locale.Language?

    // Derived — Z0, generated at save
    var title: String?                // ≤ 8 words, speakable
    var summary: String?              // 1–2 sentences, speakable
    var moodValence: Double?          // −1.0 … 1.0
    var moodLabels: [String]          // constrained vocabulary, §6.4
    var topics: [String]              // constrained vocabulary
    var salience: Double?             // 0…1, drives weekly selection

    // Context — captured, never inferred from network lookups of the user
    var placeName: String?            // coarse, user-permitted
    var weatherSummary: String?       // WeatherKit at time of capture
    var healthContext: HealthSnapshot?

    // Lifecycle
    var isFavorite: Bool
    var isArchived: Bool
    var indexState: IndexState        // .pending, .indexed, .excluded
    var excludedFromIndex: Bool       // user-set, per entry

    @Relationship(deleteRule: .cascade) var attachments: [Attachment]
    @Relationship(inverse: \Reflection.entries) var reflections: [Reflection]
}

@Model final class Reflection {
    var id: UUID
    var kind: ReflectionKind          // .entry, .weekly, .monthly
    var periodStart: Date
    var periodEnd: Date
    var generatedAt: Date

    var zone: TrustZone               // .device or .apple — persisted, shown in UI
    var modelIdentifier: String       // for eval traceability
    var promptVersion: String         // §11.3

    var body: String                  // speakable prose
    var observation: String?          // the single "worth keeping" line
    var citations: [Citation]         // entry IDs the model grounded on
    var audioAssetID: String?         // cached TTS render, §8.5

    var userRating: ReflectionRating? // for the quality study, §13
    var entries: [Entry]
}

@Model final class Citation {
    var entryID: UUID
    var quotedSpan: String?           // exact substring from the entry
    var confidence: Double?
}

@Model final class Conversation {
    var id: UUID
    var startedAt: Date
    var title: String?
    @Relationship(deleteRule: .cascade) var turns: [Turn]
}

@Model final class Turn {
    var id: UUID
    var role: TurnRole                // .user, .assistant
    var text: String
    var createdAt: Date
    var zone: TrustZone?
    var citations: [Citation]
    var wasDegraded: Bool             // true if answered on-device after PCC unavailable
}
```

**REQ-DATA-005** — `Citation` is not decorative. Every generated claim about the user's history MUST be traceable to an `Entry.id`. Ungrounded assertions are the primary quality failure mode for this product and MUST be detectable in evaluation.

### 5.3 Health integration

**REQ-DATA-006** — `HealthSnapshot` is written only with explicit HealthKit authorization, is read-only from Health, and stores coarse values: sleep duration bucket, workout occurred (bool), and `HKStateOfMind` valence if the user logs it.

**REQ-DATA-007** — Memento SHOULD offer to **write** the entry's inferred mood back to Health as an `HKStateOfMind` sample, off by default, one-tap opt-in. This makes Memento a first-class citizen of the user's own Health data rather than a silo, and it is a capability no competitor in this category currently exercises.

**REQ-DATA-008** — Health data MUST NOT be sent to PCC. Health-derived context MAY be used to *select* entries for a reflection and MAY be summarized in Z0 into a neutral phrase before inclusion in any Z1 prompt. ⚠️ VERIFY current App Review guidance on HealthKit data in third-party model prompts before implementing even the summarized path; the conservative default is to exclude entirely.

### 5.4 Audio store

**REQ-DATA-009** — Original audio is stored as files in the app container, not as SwiftData blobs. Format: compressed (AAC/Opus), quality sufficient for re-transcription. ⚠️ VERIFY codec availability and file size targets.

**REQ-DATA-010** — Audio retention is a user setting with three values: keep forever (default off), keep 30 days, discard after transcription (default). Rationale: audio is the highest-sensitivity artifact and the largest storage consumer, and most users want the words, not the recording.

**REQ-DATA-011** — Audio files MUST NOT sync to CloudKit by default. Optional, disclosed, and separately toggled.

### 5.5 Export and deletion

**REQ-DATA-012** — Full export to Markdown and JSON, including reflections and citations, generated entirely on-device, delivered via the share sheet or Files.

**REQ-DATA-013** — "Delete everything" MUST remove SwiftData store, audio files, Spotlight index entries, cached TTS renders, and CloudKit records, and MUST report completion. Partial deletion that leaves Spotlight entries behind is a P0 privacy defect.

---

## 6. Indexing and retrieval

This section replaces the entirety of the 1.3 pgvector subsystem.

### 6.1 Model

Retrieval works by **donating entries to Core Spotlight's semantic index** and then attaching `SpotlightSearchTool` to a `LanguageModelSession`. The model authors its own queries, Spotlight executes them against the semantic index, and the model reasons over the returned items. There is no chunking strategy, no embedding model, no vector store, and no similarity threshold to tune.

⚠️ VERIFY the exact tool name, initializer, and configuration surface against the iOS 27 SDK. WWDC26 session 241 and session 246 are the primary sources.

### 6.2 Donation

**REQ-IDX-001** — Every `Entry` where `excludedFromIndex == false` MUST be donated to Core Spotlight with a `CSSearchableItemAttributeSet` carrying at minimum: full transcript as textual content, title, `contentCreationDate`, mood labels, topics, and place name.

**REQ-IDX-002** — Entries MUST also conform to App Intents' `IndexedEntity` so the same donation serves Siri, Spotlight actions, and the search tool from one code path.

**REQ-IDX-003** — Implement `CSSearchableIndexDelegate` including `searchableItems(forIdentifiers:)`, so the model can retrieve the full item and see metadata the compact index cannot return. ⚠️ VERIFY signature.

**REQ-IDX-004** — Implement a Spotlight index extension for reindexing so the system can rebuild without launching the app.

**REQ-IDX-005** — Donation is incremental on save and delete. A full reindex path MUST exist and MUST be triggerable from Settings ("Rebuild search index") for support purposes.

### 6.3 The visibility problem — resolve before building

**DEC-002 — BLOCKING.** Core Spotlight is a *system* index. A journal entry donated to it may surface in system-wide search: someone picks up an unlocked iPhone, types a word, and reads a private journal line from the search results. For this product that is not a bug, it is a category-ending failure.

Required investigation, in priority order:

1. Can donation be scoped to an **app-private domain** that the app's own `SpotlightSearchTool` can query but system search cannot surface? Investigate `CSSearchableIndex` domain identifiers and any private-index API. ⚠️ VERIFY.
2. Does an attribute exist that excludes an item from system UI while keeping it retrievable by the owning app? ⚠️ VERIFY.
3. Does Data Protection class on the index respect device lock such that items are unavailable while locked?
4. If none of the above hold: what is the fallback retrieval architecture?

**REQ-IDX-006** — If DEC-002 resolves negatively (entries cannot be hidden from system search), the app MUST default `excludedFromIndex` to **true** and present indexing as an explicit opt-in with a plain-language explanation of the tradeoff — accepting that retrieval quality degrades for users who decline.

**REQ-IDX-007** — Fallback retrieval architecture, required as a designed contingency even if unbuilt: a hand-rolled `Tool` conforming to the Foundation Models tool protocol that queries SwiftData directly using date-range predicates, `NLTagger`-derived keyword matching, and mood/topic filters, returning the top-N entries as structured tool output. This is materially weaker than semantic retrieval but keeps the architecture serverless. It MUST be specified in `/specs/indexing-retrieval.spec.md` as Plan B with an explicit trigger condition.

### 6.4 Controlled vocabularies

**REQ-IDX-008** — `moodLabels` and `topics` MUST be drawn from a fixed, versioned vocabulary defined in the repo, not free-generated. Free-form tags fragment the index, make pattern detection statistically meaningless, and produce reflections that claim trends that do not exist.

**REQ-IDX-009** — Vocabulary assignment uses guided generation (`@Generable` with enum-constrained fields) on-device at entry save. The vocabulary version is stamped on the entry so a future vocabulary migration can re-tag.

### 6.5 Retrieval quality gate

**REQ-IDX-010** — Before any generative surface depending on retrieval ships, a fixture corpus of ≥ 250 entries spanning ≥ 8 months MUST be evaluated against a hand-authored question set of ≥ 40 queries with known correct entries. Pass condition: **recall@5 ≥ 0.85** on the gold set. Retrieval failure is invisible to users but poisons every downstream surface; this gate is not optional.

---

## 7. Intelligence layer

### 7.1 The boundary

**REQ-INT-001** — Exactly one Swift module MAY `import FoundationModels`. Every other module depends on protocols. This is P3 and it is enforced by build configuration, not convention.

```swift
protocol IntelligenceService: Sendable {
    func reflect(on entry: Entry) async throws -> EntryReflection
    func weeklyReflection(for week: DateInterval) async throws -> PeriodReflection
    func monthlyInsight(for month: DateInterval) async throws -> PeriodReflection
    func ask(_ question: String,
             in conversation: Conversation) -> AsyncThrowingStream<AnswerChunk, Error>
    func availability() async -> IntelligenceAvailability
}

enum TrustZone: String, Codable, Sendable { case device, apple }

struct GenerationRequest: Sendable {
    let intent: GenerationIntent      // .entryReflection, .weekly, .monthly, .ask, .title
    let preferredZone: TrustZone
    let allowsDegradation: Bool
    let promptVersion: String
    let toolsEnabled: Bool
}

struct GenerationOutcome<T: Sendable>: Sendable {
    let value: T
    let zoneUsed: TrustZone
    let modelIdentifier: String
    let wasDegraded: Bool
    let latency: Duration
}
```

**REQ-INT-002** — Every method returns the zone actually used. Callers MUST surface it. There is no API shape in which a caller can be unaware of where generation happened.

### 7.2 Routing table

**REQ-INT-003** — Routing is table-driven, not scattered conditionals.

| Intent | Default zone | Rationale | Degradation |
|---|---|---|---|
| Entry title | Z0 | Trivial, must be instant, runs on every save | none needed |
| Entry summary | Z0 | Short input, short output | none needed |
| Mood + topics | Z0 | Guided generation, constrained enums | none needed |
| Salience score | Z0 | Cheap, drives selection | none needed |
| Entry reflection | Z0 | Single-entry context fits comfortably | none needed |
| **Weekly reflection** | Z1 (PCC) | Multi-entry synthesis, needs reasoning + context | Z0 with reduced entry set, labeled |
| **Monthly insight** | Z1 (PCC) | Heaviest retrieval + synthesis | Z0 shortened form, labeled |
| **Ask (chat)** | Z1 (PCC) | Tool-calling loop + open-ended reasoning | Z0 with narrower retrieval, labeled |
| Image understanding | Z0 | On-device model now accepts image input | none |

**REQ-INT-004** — The routing table MUST be overridable by a user-facing setting (§10.2) that pins everything to Z0.

### 7.3 Quota governance

PCC has a **daily per-user limit**, higher for iCloud+ subscribers. Chat is the only unbounded consumer and will exhaust it first.

**REQ-INT-005** — A `QuotaGovernor` actor MUST track PCC consumption locally and reserve budget for scheduled surfaces. Priority order when budget is constrained: **weekly reflection > monthly insight > chat**. A user must never lose their Sunday reflection because they had a long conversation on Saturday.

**REQ-INT-006** — Chat MUST have a soft local rate limit below the system limit, so the app degrades on its own terms with a clear message rather than hitting an opaque system error.

**REQ-INT-007** — ⚠️ VERIFY the exact API for reading remaining quota, the error surfaced on exhaustion, and whether the limit is per-app or per-user-across-apps. If it is per-user-across-apps, the governor cannot know the true remaining budget and MUST be purely reactive — this materially changes the spec.

**REQ-INT-008** — iCloud+ raises the limit. The app MAY mention this factually at the point of exhaustion. It MUST NOT nag, and MUST NOT imply Memento requires iCloud+.

### 7.4 Degradation contract

**REQ-INT-009** — Degradation from Z1 to Z0 MUST be: attempted automatically, completed successfully, and disclosed in the resulting artifact — both persisted (`Reflection.zone`, `Turn.wasDegraded`) and rendered.

**REQ-INT-010** — Degraded output MUST use a different prompt tuned for the smaller model's strengths, not the PCC prompt with a smaller model behind it. Reusing the heavy prompt on the light model produces confident, ungrounded, badly structured output — the worst failure mode available.

**REQ-INT-011** — Copy for degradation is a design deliverable, not a string constant. It must convey: what happened, that nothing was lost, and what the user can do. Draft: *"Written on this device. Shorter than usual — your daily reflection allowance is used up until tomorrow."*

### 7.5 Guided generation contracts

**REQ-INT-012** — All structured outputs use `@Generable` with `@Guide` descriptions. No JSON-in-a-string parsing anywhere in the codebase.

```swift
@Generable struct EntryReflection {
    @Guide(description: "Six words or fewer. No punctuation at the end. Reads naturally aloud.")
    let title: String

    @Guide(description: "One or two sentences describing what this entry was about, in plain prose. No lists, no markdown, no headers.")
    let summary: String

    @Guide(description: "Emotional valence from -1.0 (very difficult) to 1.0 (very good).")
    let valence: Double

    @Guide(description: "Up to three moods from the provided vocabulary.")
    let moods: [MoodLabel]          // enum, closed set

    @Guide(description: "Up to four topics from the provided vocabulary.")
    let topics: [TopicLabel]        // enum, closed set

    @Guide(description: "How much this entry stands out relative to an ordinary day, 0.0 to 1.0.")
    let salience: Double
}

@Generable struct PeriodReflection {
    @Guide(description: "Three to five sentences of continuous prose. Speakable: no markdown, no bullet points, no headings, no emoji. Written in second person.")
    let body: String

    @Guide(description: "One sentence. The single observation most worth keeping. Never advice. Never a question. Never comfort.")
    let observation: String

    @Guide(description: "The identifiers of entries this reflection is grounded in. Every claim must trace to one of these.")
    let groundedEntryIDs: [String]

    @Guide(description: "True if there was not enough material this period to say anything real.")
    let hasNothingToSay: Bool
}
```

**REQ-INT-013** — `hasNothingToSay` is a first-class product feature, not an error path. When true, the app renders a deliberate empty state and generates no prose. Slate's strongest line — *when it has nothing real to say, it says nothing* — is correct product design and Memento adopts the principle without adopting the doctrine of silence generally.

### 7.6 Streaming

**REQ-INT-014** — Chat uses snapshot streaming for perceived latency. Reflections do **not** stream; they arrive complete, because they are also audio artifacts (§8) and because a reflection assembling itself word by word reads as a chatbot rather than as a considered observation. This is a deliberate divergence in interaction model between the two surfaces.

### 7.7 Provider escape hatch

**REQ-INT-015** — The `IntelligenceService` implementation MUST accept its underlying `LanguageModel` by injection. Swapping Apple's PCC model for Anthropic's or Google's conforming Swift package MUST be a single construction-site change, exercised at least once in a test target so the seam is proven rather than assumed.

**REQ-INT-016** — Shipping a non-Apple provider would change the trust boundary from Z1 to Z2 and MUST NOT occur without an explicit product decision, a privacy label change, and updated user-facing copy. The seam exists for survivability, not for convenience.

**REQ-INT-017** — Ask generation **work is proportional to classified turn complexity** (an exponential curve, not a linear nudge). Phatic greetings and continuers MUST use a distinct light bundled prompt and MUST NOT run journal retrieval or the companion ask@14 recipe. They still Open (one question except goodbye). No-RAG turns MUST stay fast and conversation-shaped. Journal questions MAY pay retrieval and the full notebook recipe. The Safety layer (REQ-SUR-004 / spec 026) MUST still run first; a channel MUST NOT skip it. Specified by spec 039.

**NON-GOAL:** Core AI custom weights in 2.0. Documented as the escape hatch below the escape hatch if Apple's models prove inadequate for reflection quality.

---

## 8. Capture and voice

### 8.1 Speech-to-text

**REQ-CAP-001** — Transcription uses `SpeechAnalyzer` with `SpeechTranscriber`, fully on-device, no `SFSpeechRecognizer`, no cloud fallback of any kind. The Gemini Audio API fallback specified in 1.3 is **deleted**.

**REQ-CAP-002** — Locale model assets MUST be checked via `AssetInventory` and downloaded with user-visible progress on first use. A journaling app that silently fails to transcribe on first launch loses the user permanently.

**REQ-CAP-003** — Live partial transcription MUST be shown during recording. Volatile results render distinctly from finalized results.

**REQ-CAP-004** — Recording MUST survive app backgrounding, lock, and interruption (call, Siri, alarm) with correct `AVAudioSession` category and interruption handling. Losing a two-minute confession to a phone call is unrecoverable trust damage.

**REQ-CAP-005** — Audio route awareness: AirPods, wired, built-in. Where a high-quality recording route is available on connected AirPods, Memento SHOULD prefer it and indicate the improved input. ⚠️ VERIFY the current API for studio-quality AirPods recording and its minimum hardware.

**REQ-CAP-006** — Multi-language: transcription locale follows a user setting defaulting to device locale. Where the `Translation` framework is available, Memento MAY offer on-device translation of a reflection into a second language for multilingual users. Lower priority; specify but do not schedule for 2.0.

### 8.2 Text capture

**REQ-CAP-007** — Typing is a first-class equal path, not a fallback. Same entity, same pipeline, `source == .text`.

### 8.3 Journaling Suggestions

**REQ-CAP-008** — Adopt Apple's **Journaling Suggestions** framework. `JournalingSuggestionsPicker` surfaces the user's own recent workouts, photos, music, podcasts, significant locations, and state-of-mind logs as journaling prompts, brokered by the system so the app receives only what the user explicitly picks.

This is strategically significant and underused: it delivers rich personal context with **zero** privacy cost to Memento, because the system does the surfacing and the user does the selecting. It is precisely the kind of integration a design-led product should own and a minimalist competitor will not build.

**REQ-CAP-009** — ⚠️ VERIFY: the Journaling Suggestions entitlement requires a request to Apple with review lead time. **File this in week 1.** It is a scheduling dependency, not an implementation detail.

**REQ-CAP-010** — A selected suggestion becomes an `Attachment` plus a seeded prompt in the composer. It MUST NOT auto-generate entry text on the user's behalf.

### 8.4 Ambient context

**REQ-CAP-011** — At capture time, with permission, record: coarse place name (`CLLocation` reverse-geocoded on-device via MapKit), and `WeatherKit` conditions. Both are optional, both are off until granted, both are stored as short strings.

Rationale: these are the cheapest possible ingredients for the pattern-finding that is Memento's core promise, and they cost the user nothing. "You've written about feeling flat on six of the last eight overcast Mondays" is the kind of observation no competitor can produce, and it requires two frameworks and no server.

**REQ-CAP-012** — Ambient context MUST be excludable per-entry and globally, and MUST never be presented as causal. Correlation language only.

### 8.5 Text-to-speech

This is the long-term differentiator and it must be designed for now, in v2.0, even if the full feature lands later.

**Constraint:** `AVSpeechSynthesizer` requires complete text before it begins generating audio; it cannot consume a token stream. This is why §7.6 specifies that reflections do not stream and chat does. **TTS belongs on reflection surfaces, not on chat.** Fighting this constraint means adding a third-party streaming TTS SDK, which violates P1 and the privacy story. Do not.

> **Amended 2026-08-18 (specs 030–036).** The constraint above is a true statement
> about `AVSpeechSynthesizer` and remains binding on that path, which the app keeps
> permanently as its degradation target. It is **not** a statement about speech
> synthesis. The final sentence was a vendor rule standing in for a privacy rule,
> and it accidentally forbade fully-local engines — the only kind that can satisfy
> the privacy rule completely. The test is now stated directly in `REQ-TTS-001`:
> local execution, zero network egress, license-cleared. Cloud and hybrid TTS
> remain forbidden. Chat has been speakable since `StreamingSentenceChunker`
> shipped; see §8.6.

**REQ-VOX-001** — Every `Reflection` MUST be renderable as audio via `AVSpeechSynthesizer` using an Enhanced or Premium system voice, with the required voice asset download surfaced in Settings. **Amended 2026-08-18 (`DEC-011`):** the neural catalog (§8.6) replaces the system-voice picker as the user-facing choice; this requirement now governs the **fallback path only** — when `AVSpeechSynthesizer` is serving, it MUST still resolve the best available Enhanced/Premium voice rather than degrading silently to a compact one.

**REQ-VOX-002** — Personal Voice support: request authorization via `AVSpeechSynthesizer.requestPersonalVoiceAuthorization()`; when granted, enumerate available personal voices and offer them for reflection playback. Generation is on-device (Z0). ⚠️ VERIFY current third-party access rules and any App Review restrictions on Personal Voice usage outside accessibility contexts.

**REQ-VOX-003** — Personal Voice is a **delighter tier**, never a default and never a gate. Training requires roughly fifteen minutes of the user reading phrases aloud; most users will not do it, and the ones who do will care deeply. Onboarding MUST NOT introduce it. It is discovered later, at a moment of demonstrated engagement — after a user's third or fourth weekly reflection.

**REQ-VOX-004** — Rendered audio for a reflection is cached (`Reflection.audioAssetID`) so replay is instant and does not re-synthesize. **Amended 2026-08-18:** never implemented, and the premise is now weak — a neural engine at the target real-time factor synthesizes a reflection faster than reading a cached file avoids doing so, and a cache invalidated on every voice change is mostly cold in practice. Spec `018` R7 carries the written verdict; do not build the cache on the strength of this line alone.

**REQ-VOX-005** — Playback MUST support background audio, lock screen controls, `MPNowPlayingInfoCenter` metadata, AirPlay, and CarPlay-safe audio session configuration. A Sunday reflection listened to on a walk is the intended use, and that means it must behave like a proper audio app, not like a button that makes noise.

**REQ-VOX-006 — Speakable output is a prompt contract.** Every prompt producing user-facing prose MUST forbid markdown, bullet points, headings, emoji, parentheticals, and numerals-as-digits where words read better. Reflection body text is validated against a `SpeakabilityLinter` in tests: no `#`, `*`, `-` list markers, no URLs, no `\n\n` runs greater than one. Violations fail the build.

**REQ-VOX-007** — ⚠️ VERIFY whether iOS 27 introduced any newer speech synthesis API beyond `AVSpeechSynthesizer`; WWDC26 material reviewed for this document did not surface one, and the assumption is that it did not. **Resolved 2026-07-25 (V18): none shipped.** §8.6 is the answer to the question this was really asking — the way past `AVSpeechSynthesizer`'s limits is not a newer Apple API, it is a local model.

### 8.6 On-device neural voice

*Added 2026-08-18. Mints the `REQ-TTS-` series. Owned by specs `030`–`036`; API truth in `technology/13-neural-tts-coreml.md`.*

`AVSpeechSynthesizer` gave the product a voice it does not control: it cannot be streamed into, its character is whatever the user happened to download, and it caps the ceiling on the one feature §8.5 calls the long-term differentiator. A local neural engine — one shared model plus per-voice style vectors, running on the Neural Engine, emitting PCM buffers the app schedules itself — removes all three limits without moving a single word off the device. The `AVSpeechSynthesizer` path stays permanently as the degradation target, which is also what keeps §8.5 true.

**REQ-TTS-001 — On-device only, zero egress.** TTS synthesis MUST execute entirely on-device. The TTS path MUST make **zero network calls** at synthesis time, model-load time, or voice-selection time. Third-party engines are permitted where fully local, license-cleared per the dependency allowlist (`REQ-MON-005`), and free of network egress. Cloud or hybrid TTS remains forbidden. This supersedes the vendor-shaped phrasing in §8.5.

**REQ-TTS-002 — Assets ship in the binary.** Model assets MUST be vendored into the repository and **bundled in the app**, not downloaded. Integrity is a **build-time** property: the recipe that produced the shipped artifact is committed alongside it and pins the source's checksum. There is no runtime download, no manifest served anywhere, and therefore no partial or corrupt state to design around — the bundle is code-signed with the app or it does not launch. *(Rewritten 2026-08-18, `DEC-012`; supersedes two earlier designs — self-hosted, then Apple-hosted, Background Assets.)*

**REQ-TTS-003 — Degradation is a permanent path, not a stopgap.** While assets are absent, downloading, or unusable, every voice feature MUST fall back to `AVSpeechSynthesizer` (`REQ-VOX-001`). No feature may hard-block on a model download, and no engine failure may surface as silence or a crash.

**REQ-TTS-004 — One engine boundary.** Exactly one module may import `CoreML`. It owns every model object, is warmed on user-intent signals rather than on the play action, accepts cooperative cancellation, and releases its models under memory pressure. This is the same containment rule as P3 (`FoundationModels`), for the same reason: it keeps a future model swap to one file.

**REQ-TTS-005 — Perceived latency is the metric.** Synthesis is pipelined against playback so audio starts before generation finishes, and a turn's perceived start is measured from end-of-user-speech to first audible sample. Instrumented, unmasked latency is recorded alongside it; masking must never be allowed to hide a regression in the real number.

**REQ-TTS-006 — Voices are data.** A voice is a style vector, not a model. Switching voices MUST NOT reload, recompile, or re-warm anything, and the UI MUST NOT fake a loading state for it. Voices are presented to the user by character, not by gender.

**REQ-TTS-007 — Two audio paths, named and explicit.** Read-back uses a high-fidelity playback configuration. Hands-free conversation uses a voice-processing configuration with echo cancellation. Transitions between them are explicit state-machine events; no playback code changes the session category implicitly.

**REQ-TTS-008 — Spoken form is a transform, and tags are an allowlist.** Text bound for synthesis passes through a spoken-form normalizer for cases where spoken register differs from display register. Expression tags come from a closed allowlist; arbitrary tag pass-through MUST be impossible by construction.

**REQ-TTS-009 — Licensing is a gate, not a footnote.** No GPL or GPL-contaminated component may appear anywhere in the text-processing (G2P / phonemizer / normalizer) path of any TTS engine. Any candidate engine MUST document its full text-front-end dependency chain before entering evaluation. Where model weights carry attribution conditions, the attribution ships in the app.

**REQ-TTS-010 — The privacy claim is substantiated, not asserted.** The zero-egress result of `REQ-TTS-001` MUST be demonstrated by proxy capture and archived as a release artifact. Public copy about the voice feature MUST NOT exceed what that artifact proves, and MUST stay inside `REQ-POS-001` and the forbidden-phrase rule.

#### Decisions this section opens

**DEC-008** — Does the flow-matching graph stay on the Neural Engine with dynamic latent length, or must it be exported as fixed-shape buckets? Dynamic shapes keep one graph and arbitrary input lengths; bucketing costs roughly 3× storage for the text-to-latent module, forces input padding, and caps a single synthesis call at the largest bucket. **Blocking for:** the engine spec's whole interior. **Owning spec:** 031. **Resolves on:** V29 (Core ML performance report, physical device). **Recommendation:** write nothing until measured — the failure mode is silent, and guessing wrong costs a rewrite rather than a tweak.

**DEC-009** — Is the provisional four-voice roster the shipping roster, once auditioned **through** the echo-cancelled conversation path rather than a clean playback path? **Blocking for:** the voice catalog, the pre-rendered previews, and the per-voice turn-start clips. **Owning spec:** 033. **Resolves on:** V30 (device audition). **Recommendation:** audition before the picker is built, not after. A voice users have bonded with cannot be swapped cheaply, and voice processing is where a warm voice turns thin.

**DEC-010** — Where does model-weight attribution live? The weights ship under a license with an attribution condition, which makes this a compliance obligation rather than a courtesy. **Owning spec:** 030. **Recommendation — RESOLVED 2026-08-18:** a dedicated Acknowledgments screen under Settings → About, shipping in the first release that includes the engine. The app has no such screen today; it also has an unreferenced font license sitting in `Resources/Fonts/OFL.txt` that belongs there.

**DEC-012** — Ship the voice model **inside the app binary**, or deliver it as a downloadable asset pack? Bundling costs app size — the binary goes from ~8.5 MB to ~156 MB, paid by every user at install whether or not they use voice — and constrains precision, since FP16 would push past the App Store's "Ask If Over 200 MB" cellular prompt. Downloading keeps the binary small but requires delivery machinery, a partial-state UX, integrity verification, and hosting that someone has to own. **Blocking for:** spec 030 in its entirety. **RESOLVED 2026-08-18 (owner): bundle.** The voice then works on first launch, in airplane mode, forever, with no state in between; the privacy claim becomes structural rather than verified; and the delivery, hosting and verification workstreams disappear. The size cost is met by palettizing `VectorEstimator` to 8-bit, which lands the app near 156 MB — under the prompt threshold with the vocoder untouched.

**DEC-011** — Does the neural catalog **replace** the system-voice picker, or sit alongside it? Replacing gives one coherent voice story and a roster the product controls; keeping both preserves user access to Enhanced/Premium and Personal Voice as *selectable* options. **Owning spec:** 033. **RESOLVED 2026-08-18 (user):** replace. The four neural voices become the only user-facing choice; `AVSpeechSynthesizer` remains as the invisible fallback (`REQ-TTS-003`), which amends `REQ-VOX-001`'s user-facing half. Personal Voice (`REQ-VOX-002`/`003`) is unaffected in principle but its discovery flow is still gated on V6, so nothing is lost today — spec 033 records how it re-enters the picker if V6 ever closes positive.

---

## 9. Surfaces

Build order is prescriptive. Each surface has a Z-zone, a degradation story, and an exit criterion.

### 9.1 Capture (Z0)

Single primary action. Press, speak, done. Live partial transcript. No mode selection, no template picker, no mood-wheel-before-you-write. The composer opens in under 400ms from cold launch, from widget, from Control Center, and from Watch.

**Exit criterion:** a two-minute spoken entry survives a phone call, an app switch, and a lock, and appears fully transcribed with title, summary, mood, topics, and index donation complete, in airplane mode.

### 9.2 Entry reflection (Z0)

Generated at save. One short summary, mood, topics, and — only when salience warrants — a single observation. Most entries get no observation. The restraint is the design.

**Exit criterion:** p50 generation latency under 2 seconds on the minimum Apple Intelligence device; observation suppressed on ≥ 60% of ordinary entries in the fixture corpus.

### 9.3 Weekly reflection (Z1 → Z0)

The head-to-head surface against Slate. Generated Sunday via `BGProcessingTask`, notified when ready, readable and **listenable**. Grounded in citations the user can tap to reach the original entry. Renders `hasNothingToSay` as a real state.

**Exit criterion:** ≥ 80% "this was worth reading" in the quality study; ≥ 95% citation accuracy; audio render available within 5 seconds of opening.

### 9.4 Patterns / monthly (Z1 → Z0)

The surface where Apple-ecosystem depth becomes visible product value. Swift Charts visualizations over mood valence, topic frequency, capture cadence, and — where authorized — sleep, workouts, weather, and place. Narrated by a monthly reflection that reads the chart, not the other way around.

**REQ-SUR-001** — Every charted correlation MUST show its n. A pattern claimed over four entries is noise, and the UI must make that legible rather than let the prose imply significance.

### 9.5 Ask (Z1 → Z0)

Conversational retrieval over history. Channelled generation (spec 039 /
`REQ-INT-017`): simple turns skip RAG and use `chat-light@4`; journal
questions attach retrieval, snapshot streaming, citations when grounded.

**REQ-SUR-002** — The assistant persona is an **archivist, not a therapist** on
**notebook** turns. It reports what the user said and when. It does not advise,
diagnose, comfort, or reassure. Phatic turns are ordinary conversation (spec
039), still not therapy. Enforced in system instructions and verified by
adversarial evaluation.

**REQ-SUR-003** — When a **journal** question cannot be answered from the corpus, the assistant says so and shows what it searched. It MUST NOT answer from general world knowledge about the topic. "I don't find anything about your brother before March" is the correct answer. This obligation does **not** apply to phatic/continuer/companion turns that must not retrieve (spec 039).

**REQ-SUR-004** — Crisis-adjacent content: if a user's question or an entry indicates acute distress, the app surfaces a static, respectful, region-appropriate resource card. It does **not** generate crisis counseling. This is specified once, centrally, and applies to every generative surface. Route to `/specs/safety.spec.md`.

### 9.6 Background generation

**REQ-SUR-005** — Weekly and monthly generation scheduled via `BGProcessingTask` requiring network and, where PCC is used, external power preferred. Failure MUST retry with backoff and MUST fall back to foreground generation on next launch rather than silently skipping a week.

---

## 10. System integration

This section is where the Apple-ecosystem strategy converts into defensibility. Each item is cheap individually; together they are a moat a minimalist competitor structurally will not build.

### 10.1 App Intents

**REQ-SYS-001** — Expose as `AppIntent`, with `AppShortcutsProvider` phrases:
- **New entry** (with optional spoken content parameter — dictate an entry to Siri without opening the app)
- **Read my weekly reflection** (returns audio)
- **Ask my journal** (parameterized question, returns a snippet)
- **Find entries about** (parameterized, returns entity results)

**REQ-SYS-002** — `Entry` conforms to `AppEntity` and `IndexedEntity` with an `EntityQuery` supporting property-based and string-based lookup, so Siri and Spotlight can act on entries directly.

**REQ-SYS-003** — Per-intent privacy declarations MUST be used where available to keep sensitive interactions on-device. ⚠️ VERIFY the iOS 27 privacy manifest declarations for intent routing.

**REQ-SYS-004** — SiriKit is deprecated in iOS 27. No SiriKit code.

### 10.2 Widgets, Controls, Live Activities

**REQ-SYS-005** — Home Screen widget: one-tap capture; last reflection's observation line in the medium size.
**REQ-SYS-006** — Lock Screen widget: capture, and streak-free "days since last entry" only if it can be phrased without shame. If it cannot, omit it — see NON-GOAL on gamification.
**REQ-SYS-007** — Control Center control: start recording. This is the fastest path to capture on the device and it costs almost nothing to build.
**REQ-SYS-008** — Live Activity during recording: elapsed time, waveform, stop action. Dynamic Island presentation required.

### 10.3 Watch

**REQ-SYS-009** — watchOS companion: capture only, with on-watch transcription where supported and deferred transcription where not. Complication for one-tap capture. Sync via the shared CloudKit container.

**REQ-SYS-010** — Watch capture is the highest-value integration for a voice journal and SHOULD be scoped for 2.1 rather than 2.0 unless the timeline permits. Specify it now so the data layer does not have to change later.

### 10.4 Focus and Shortcuts

**REQ-SYS-011** — Provide a Focus filter so a "Wind Down" or "Personal" Focus can surface Memento's capture prompt. Provide Shortcuts actions matching every App Intent so users can build their own automations — a small audience, disproportionately vocal, and exactly the audience that writes about apps.

### 10.5 Accessibility

**REQ-A11Y-001** — Full VoiceOver, Dynamic Type through accessibility sizes, Reduce Motion, and Increase Contrast support. Non-negotiable.
**REQ-A11Y-002** — Every reflection is audio-renderable, which makes the app substantially usable without reading. Lean into this; it is a genuine accessibility strength that emerges from the TTS work at no extra cost.
**REQ-A11Y-003** — Voice Control compatibility: all primary actions must have clear accessibility labels usable as spoken targets.

### 10.6 Design system

**REQ-SYS-012** — Liquid Glass, second-iteration tokens, verified against the transparency-reduction accessibility control.
**REQ-SYS-013** — Foldable layout APIs: hinge-state handling in SwiftUI. Low effort, and the hardware ships this fall.
**REQ-SYS-014** — Core Haptics for capture start/stop and reflection-ready. Haptics are an underused emotional design surface in this category.

---

## 11. Prompt architecture

### 11.1 Loss from 1.3

The `prompts` table with versioning, one-hour in-memory cache, hardcoded fallback, and Git-markdown workflow allowed prompt iteration without redeployment. Removing Supabase removes that. This is the single genuine capability regression in the rebuild and must be handled deliberately rather than mourned.

### 11.2 Replacement

**REQ-PRM-001** — Prompts ship in-bundle as versioned resources, authored in Markdown in the repo, compiled into the binary at build time. This is the fallback layer and is always present.

**REQ-PRM-002** — An optional remote prompt manifest MAY be fetched from a static host (signed JSON, CDN, no server logic). Constraints: **request contains no user data, no identifier, no query parameters**; fetch is weekly at most; failure is silent and falls through to bundled prompts; signature verification is mandatory before use.

**REQ-PRM-003** — REQ-PRM-002 conflicts with a strict "no network calls" reading. Memento does not make that claim (REQ-POS-001), so this is permissible — but it MUST be disclosed in the privacy explainer, and the fetch MUST be disableable in Settings.

**DEC-003** — Ship remote prompts in 2.0, or defer to 2.1 and accept App Store review latency for prompt fixes? Shipping it means the privacy explainer must be more nuanced from day one. **Recommendation:** build the mechanism, ship it disabled, enable in 2.1 once the privacy narrative is established.

### 11.3 Versioning and evaluation

**REQ-PRM-004** — Every generated artifact persists `promptVersion` and `modelIdentifier`. Without this, the quality study cannot attribute regressions and is worthless.

**REQ-PRM-005** — A golden-set evaluation harness MUST exist: fixture corpus, fixed question set, prompt version under test, output captured to disk for manual review. Runs locally, ships with the repo, requires no service.

---

## 12. Monetization and dependencies

### 12.1 Pricing

Current plan: $9.99/mo, $79/yr. Slate: $7.99/mo, $59.99/yr with a one-month trial.

**Observations for the pricing decision, not conclusions:**
- Marginal inference cost is now approximately zero on both sides. Neither app can justify price by COGS.
- Slate has established that consumers will pay a subscription for a zero-marginal-cost local app. That de-risks the model.
- Memento's feature surface is materially larger. A premium to Slate is defensible; a 25–33% premium is a specific claim about perceived value that should be tested rather than assumed.
- An annual-first presentation suits a journaling product, where the value proposition is explicitly longitudinal. Selling a monthly plan for an app whose core promise is "a year from now this will know you" is a positioning mismatch.

**DEC-004** — Final price and trial length. **Blocking for:** paywall spec, App Store Connect configuration.

### 12.2 Implementation

**REQ-MON-001** — StoreKit 2 with RevenueCat for receipt validation and subscriber analytics. RevenueCat receives purchase events and an anonymous identifier. **No content, no derived data, no user text, ever.**
**REQ-MON-002** — App Store Small Business Program enrollment is **mandatory** — it is the eligibility condition for free PCC access, not merely a commission benefit.
**REQ-MON-003** — Free tier: unlimited capture, transcription, timeline, search, export. Paid: reflections, patterns, ask, Personal Voice. Rationale: never hold a user's own words hostage. The words are theirs; the intelligence is the product.

### 12.3 Privacy label

**REQ-MON-004** — Target label: **Data Not Collected**, contingent on RevenueCat's SDK not triggering a collection disclosure for purchase data. ⚠️ VERIFY. If it does, evaluate StoreKit 2 direct and accept the loss of subscriber analytics. The label is worth more than the dashboard.

### 12.4 Dependency allowlist

| Dependency | Justification | Reviewable |
|---|---|---|
| RevenueCat | Receipt validation, subscription state | Yes — see REQ-MON-004 |
| Neural TTS integration surface | The one voice engine the product controls; fully local, zero network egress at synthesis, model-load, or voice-selection time | Yes — see REQ-TTS-001, REQ-TTS-009, and spec 030 |
| *(nothing else)* | | |

**Added 2026-08-18 (specs 030–036).** Model *weights* are not an SPM package and are not governed by this table — their integrity is governed by spec 030's compiled-in manifest (`REQ-TTS-002`) and their licensing by `REQ-TTS-009`. The distinction matters because the CI check enforcing this table reads package identities only; weights would pass it invisibly.

**REQ-MON-005** — Any addition to this table requires an explicit decision record. The near-zero third-party surface is a marketing asset and a security posture simultaneously.

---

## 13. Evaluation and the quality study

**REQ-EVAL-001** — The 30-day AI quality study designed for 1.3 is **paused and re-baselined**. Running it against pgvector + Gemini would validate an architecture about to be deleted. Its structure — three cohorts, daily micro-surveys, weekly check-ins, end-of-study survey, exit interviews — survives intact.

**REQ-EVAL-002** — Revised success metrics:

| Metric | Target | Measured how |
|---|---|---|
| Retrieval recall@5 | ≥ 0.85 | Automated, golden set, pre-ship gate |
| Reflection rated helpful | ≥ 80% | In-app micro-survey |
| Citation accuracy | ≥ 95% | Manual review of sampled reflections |
| Ungrounded claim rate | ≤ 2% | Manual adversarial review |
| Persona adherence (no advice) | ≥ 98% | Adversarial prompt suite |
| Willingness to pay | ≥ 70% | End-of-study survey |
| Z0 fallback satisfaction | ≥ 60% of Z1 baseline | Forced-degradation cohort |
| p50 entry reflection latency | < 2s | Instruments |

**REQ-EVAL-003** — Add a **forced-degradation cohort**: participants pinned to Z0 for the full study. If on-device-only satisfaction is close to PCC satisfaction, that is a major finding — it means the true product can make the absolute privacy claim, and the positioning in §1.3 should be revisited before launch rather than after.

**REQ-EVAL-004** — Instrument with the Xcode 27 Foundation Models instrument for tool-call loops, time-to-first-token, and latency attribution. Do not build custom timing infrastructure.

**REQ-EVAL-005** — All study telemetry is **manually collected via surveys and interviews**. No in-app analytics SDK. This is slower and it is the price of the privacy label.

---

## 14. Migration and sequencing

### 14.1 Deletion manifest

| Removed | Replacement | Risk |
|---|---|---|
| Supabase Postgres + pgvector | SwiftData + Core Spotlight | Retrieval quality — gated by REQ-IDX-010 |
| Embeddings pipeline (`text-embedding-004`) | Semantic Spotlight index | Same gate |
| Retrieval Edge Function | `SpotlightSearchTool` | Same gate |
| `generate-insights` Edge Function | `LanguageModelSession` on PCC | Quality — gated by Phase 0 spike |
| Gemini 2.0 Flash integration | Foundation Models model slot | Quality; escape hatch REQ-INT-015 |
| Supabase Auth | ~~Sign in with Apple (built)~~ **Removed — no replacement** (amended 2026-07-23, see note below) | Low |
| Supabase `prompts` table | §11 | Operational regression, accepted |
| Gemini Audio transcription fallback | `SpeechAnalyzer` only | Low |
| Deno/TypeScript Edge Function codebase | — | Entire runtime removed |

**Amendment (2026-07-23):** by product decision, Memento 2.0 has **no accounts at
all** — the original "Sign in with Apple" replacement is superseded. This makes
§1.3's positioning claim ("No account.") literally true rather than
approximately true. Identity is a locally stored display name collected in
onboarding; the onboarding-complete gate is a local flag; App Review's
demo-account requirement (guideline 2.1) becomes moot. Specified in
`specs/023-no-account-experience.md`; the front-end that survives this change is
contracted in `specs/reference/frontend-preservation-contract.md`.

**REQ-MIG-001** — Existing 1.3 TestFlight users, if any, MUST have a migration path exporting their entries from Supabase and importing to SwiftData, run once, on-device, before the server is decommissioned. If the user count is zero, document that and skip.

### 14.2 Phase plan

**Phase 0 — De-risk (weeks 1–2). Nothing is deleted in this phase.**
- File Small Business Program verification and the PCC access application.
- File the Journaling Suggestions entitlement request.
- Build the fixture corpus: ≥ 250 synthetic entries, ≥ 8 months, ≥ 40 gold questions.
- **Spike A:** Spotlight donation + `SpotlightSearchTool`, measured against REQ-IDX-010.
- **Spike B:** weekly reflection on AFM 3 on-device vs PCC vs current Gemini output, blind-rated.
- **Spike C:** resolve DEC-002 (system search visibility). Highest-priority unknown in the document.

*Gate: Spike A pass, Spike C resolved. If Spike A fails, activate REQ-IDX-007 Plan B and re-scope.*

**Phase 1 — Subtract (weeks 3–4).**
Delete the Supabase tier. Rebuild data layer per §5. Implement donation and indexing per §6. Ship an internal build with capture, timeline, search, export, and no AI at all. This build must be excellent on its own; if the app is not good without intelligence, intelligence will not save it.

**Phase 2 — Intelligence boundary (weeks 5–6).**
`IntelligenceService`, `ModelRouter`, `QuotaGovernor`, `PromptRegistry`, generation contracts. Entry reflection (Z0) end to end. Evaluation harness.

**Phase 3 — Surfaces (weeks 6–8).**
Weekly, then monthly/patterns, then Ask. Ask is last: highest variance, highest quota consumption, highest safety surface.

**Phase 4 — Voice and system (week 8–9).**
TTS with system voices. Personal Voice behind the delighter gate. App Intents, widgets, Control Center, Live Activity.

**Phase 5 — TestFlight and study (weeks 9–12).**
Internal TestFlight, then re-baselined 30-day study. Target public launch aligned to iOS 27 general availability, which is both a technical requirement and a discoverability event — Apple features apps that adopt new APIs at release, and that is distribution that cannot be purchased.

### 14.3 Effort

The 90-hour / 4-week estimate from the 1.3 checklist is approximately preserved. Roughly 30 hours of previously planned work is deleted (RAG backend, Edge Functions, embeddings, prompt infrastructure); roughly the same is added (Spotlight donation, intelligence boundary, quota governance, TTS). The calendar is longer because it is gated on iOS 27 GA, not because it is more work.

---

## 15. Open decisions — resolve before spec derivation

| ID | Decision | Blocks | Priority |
|---|---|---|---|
| **DEC-002** | Can Spotlight donation be hidden from system-wide search? | Entire retrieval architecture | **P0** |
| DEC-001 | Ship on non-Apple-Intelligence devices? | Monetization, App Store listing | P1 |
| DEC-004 | Final pricing and trial length | Paywall spec | P1 |
| DEC-003 | Remote prompt manifest in 2.0 or 2.1? | Privacy explainer copy | P2 |
| DEC-005 | Watch companion in 2.0 or 2.1? | Scope | P2 |
| DEC-006 | Does HealthKit-derived context enter Z1 prompts at all? | Health spec, App Review | P1 |
| DEC-007 | Audio retention default — is "discard after transcription" right? | Data spec, onboarding | P2 |
| DEC-008 | ANE placement with dynamic latent length, or fixed-shape buckets? | Neural engine interior (spec 031) | P1 |
| DEC-009 | Is the provisional voice roster the shipping roster, auditioned through AEC? | Voice catalog, previews, turn-start clips (spec 033) | P1 |
| DEC-010 | Model-weight attribution placement | Acknowledgments screen (spec 030) | ✅ resolved 2026-08-18 |
| DEC-011 | Does the neural catalog replace the system-voice picker? | Voice picker, `REQ-VOX-001` (spec 033) | ✅ resolved 2026-08-18 |

---

## 16. Verification queue

**Superseded as the operational tracker** by
`specs/reference/technology/11-verification-queue.md` (28 items, V1–V28,
same confidence-marker convention, actively maintained) — use that list to
pick up and close verification work. The list below is kept **for REQ-/DEC-
provenance only**: it's what specs 013–022 cite by number, and item 2 below
is `DEC-002`, tracked to closure in spec 013.

**Numbering map (§16 item → V-queue), with status as of the July 2026
technology-library review** — several items below are already partially or
fully resolved by verified WWDC26 session material; check the V-queue entry
before spending verification effort:

| §16 | V-queue | Status |
|---|---|---|
| 1 | V9, V10, V11, V12 | Core `SpotlightSearchTool` API ✅ verified (init, config, `searchResults` cases); remaining: `sources` case list, tool registration form, `ToolCallingMode`, registered tool name |
| 2 | **V1** | Open — P0, the named-index hypothesis is the first test |
| 3 | — | ✅ Resolved — `searchableItems(forIdentifiers:)` verified (technology/03 §4); compile-check only |
| 4 | V4, V13 | Quota API surface ✅ verified (`quotaUsage.status`/`isApproachingLimit`/`isLimitReached`/`limitIncreaseSuggestion`); remaining: per-app vs per-user scope (V4, plan for per-user), full `status` case list (V13) |
| 5 | V2 | Open — file week 1 |
| 6 | V3 | Open — file week 1 |
| 7 | V6 | Open |
| 8 | V18 | Open (assumption: none shipped) |
| 9 | V17 | Open |
| 10 | V5 | Open |
| 11 | V7 | Open |
| 12 | V8 | Open |
| 13 | V20 | Open |
| 14 | V28 | Context sizes ✅ verified (4096 iOS 26 / 8192 iOS 27 newer devices on-device; 32768 PCC; read `contextSize` at runtime); remaining: on-device latency on minimum supported hardware (V28) |
| 15 | V27 | Open |

Every `⚠️ VERIFY` in this document, consolidated. Each MUST be confirmed against the iOS 27 SDK and current Apple documentation before the dependent spec is finalized. This document was assembled from WWDC26 session material and secondary sources; API surfaces in developer beta change.

1. `SpotlightSearchTool` exact API surface, configuration, and result shape *(§6.1)*
2. App-private Spotlight domain / system-search exclusion *(§6.3 — DEC-002, P0)*
3. `searchableItems(forIdentifiers:)` signature *(§6.2)*
4. PCC quota API: readable remaining budget, per-app vs per-user scope, exhaustion error *(§7.3)*
5. PCC application process, approval lead time, eligibility confirmation *(§14.2)*
6. Journaling Suggestions entitlement request and lead time *(§8.3)*
7. Personal Voice third-party access rules and App Review posture *(§8.5)*
8. Any iOS 27 speech synthesis API beyond `AVSpeechSynthesizer` *(§8.5)*
9. AirPods high-quality recording API and hardware minimums *(§8.1)*
10. `NSFileProtectionComplete` vs background task execution *(§5.1)*
11. HealthKit data in third-party model prompts — App Review guidance *(§5.3)*
12. RevenueCat SDK impact on "Data Not Collected" privacy label *(§12.3)*
13. Per-intent privacy manifest declarations in App Intents *(§10.1)*
14. AFM 3 Core Advanced context window and on-device latency on minimum supported hardware *(§7.2)*
15. Audio codec availability and target file sizes *(§5.4)*

---

## 17. Derived spec checklist

A derived spec is complete when it contains all of the following:

- [ ] Traceability table mapping every section requirement to a `REQ-` ID in this document
- [ ] Swift interface contracts for every public type it introduces
- [ ] State machine for every multi-step or asynchronous flow
- [ ] Error taxonomy with user-facing copy for each error, written as design copy not developer strings
- [ ] Zone tag (Z0/Z1/Z2) for every operation
- [ ] Degradation behavior for every Z1 operation
- [ ] Acceptance criteria in Given/When/Then form
- [ ] Test plan naming specific fixtures, using Swift Testing
- [ ] Its subset of the §16 verification queue, with each item marked confirmed or outstanding
- [ ] Explicit non-goals restating what a helpful implementation agent must not add

---

*End of document.*
