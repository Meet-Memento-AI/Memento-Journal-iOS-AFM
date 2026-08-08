---
id: 015
title: Data Layer — SwiftData and CloudKit
tier: P0
status: in-progress (2026-07-24) — Requirements derived; implementation blocked on Xcode 27 beta for the deployment-target bump, unblocked portions noted per-requirement
effort: 3 sessions
depends_on: [013, 014, 023]
findings: [schema-mirroring-deltas, cloudkit-error-taxonomy, health-z0-statistics, audio-as-files, five-store-deletion-test, capability-tier-at-launch]
source_refs: [REQ-DATA-001, REQ-DATA-002, REQ-DATA-003, REQ-DATA-004, REQ-DATA-005, REQ-DATA-006, REQ-DATA-007, REQ-DATA-008, REQ-DATA-009, REQ-DATA-010, REQ-DATA-011, REQ-DATA-012, REQ-DATA-013, REQ-PLAT-001, REQ-PLAT-002, REQ-PLAT-003, REQ-PLAT-004, DEC-006, DEC-007]
tech_refs: [technology/05-data-swiftdata-cloudkit.md, technology/08-context-frameworks.md]
---

# 015 — Data Layer: SwiftData and CloudKit

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§4 "Platform baseline" and §5 "Data layer" in full. Supersedes spec
[003](003-database-baseline-and-account-deletion.md) (Supabase database baseline —
obsolete).

## Why

This is the foundational subtraction-and-rebuild: delete `supabase/` (Postgres,
pgvector, 6 edge functions, auth) and replace the system of record with SwiftData
(authoritative) + CloudKit private-DB mirroring (replication only, per P2). Every
other 2.0 spec's entities — `Entry`, `Reflection`, `Citation`, `Conversation`,
`Turn` — are defined here. Nothing downstream (indexing, intelligence, capture,
surfaces) can be built until this schema exists.

## Technology References

- `specs/reference/technology/05-data-swiftdata-cloudkit.md` — primary:
  SwiftData `ModelConfiguration`/`ModelContainer` CloudKit-mirroring
  constraints, `NSFileProtection` levels, audio-as-files retention options,
  and the 5-part deletion requirement.
- `specs/reference/technology/08-context-frameworks.md` — `HKStateOfMind`
  read/write API shape for `DEC-007`'s HealthKit write-back decision.

## Current State (evidence)

No `@Model` classes or `import SwiftData` anywhere in `MeetMemento/` (confirmed
2026-07-23). Current persistence is Supabase Postgres via `supabase-swift`, with
plain `Codable` structs in `MeetMemento/Models/` (`Entry.swift`, `JournalEntry.swift`,
`ChatSession.swift`, `Insight.swift`/`UserInsight.swift`, etc.) — see this spec's
Tasks for the mapping from each old model to its new `@Model` equivalent.
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` in `MeetMemento.xcodeproj/project.pbxproj`
(needs raising to 27.0 per `REQ-PLAT-001`).

## Requirements

**Traceability:** R1 → `REQ-DATA-005`, `REQ-DATA-002` (schema half), source doc
§5.2; R2 → `REQ-DATA-001`, `REQ-DATA-002` (store half), V25; R3 → `REQ-DATA-003`,
`REQ-DATA-004`; R4 → `REQ-DATA-006`, `REQ-DATA-007`, `REQ-DATA-008`, `DEC-006`
(OPEN); R5 → `REQ-DATA-009`, `REQ-DATA-010`, `REQ-DATA-011`, `DEC-007` (OPEN);
R6 → `REQ-DATA-012`, `REQ-DATA-013`; R7 → `REQ-PLAT-001` … `REQ-PLAT-004`;
R8 → `REQ-MIG-001`; R9 → this spec's §16 verification-queue subset (items 10,
11, 15 + V25). Zone tags per spec 014 R1's `TrustZone` contract — cited, never
reinvented. **Xcode 27 gate, stated once:** the iOS 27 SDK is required for the
deployment-target bump (R7) and for every 🔴 API verification below (V5, V25,
V27). The Xcode 27 beta (beta 4, 27A5228h) was **installed and API-swept
2026-07-26** (spec 013 task 8), so the SDK is available and the bump plus
SDK-only checks are unblocked; what remains gated is **on-device** verification
of the device-dependent items (V5, V25, V27) on a physical iOS 27 device.
Requirements below note per-block what is unblocked regardless.

### R1. `@Model` schema — interface contracts and mirroring deltas
The canonical entity definitions are source doc §5.2, adopted **verbatim as the
contract** for `Entry`, `Reflection`, `Citation`, `Conversation`, `Turn` — this
spec does not restate those ~80 lines; it specifies the deltas the CloudKit
mirroring rules (`REQ-DATA-002`, `technology/05` §2) force on them, plus the
supporting types §5.2 references but does not define:

**Mirroring deltas to §5.2 (all four constraints checked per property):**
- Every non-optional property gains a default value in the actual declaration
  (`transcript: String = ""`, `moodLabels: [String] = []`, `isFavorite = false`,
  `indexState: IndexState = .pending`, …) — CloudKit has no required fields on
  existing records. The §5.2 shapes are unchanged; only defaults are added.
- No `@Attribute(.unique)` anywhere — uniqueness of `id: UUID` is enforced in
  application logic (fetch-before-insert), not the schema.
- Every relationship declares an inverse — §5.2 already shows
  `Entry.reflections ↔ Reflection.entries`; the same must be made explicit for
  `Entry.attachments`, `Conversation.turns`, and the `Citation` linkage
  (`Reflection.citations`/`Turn.citations` — note `Citation.entryID` is a plain
  `UUID`, deliberately *not* a relationship, so a cited entry can be deleted
  without cascading into historical reflections). `Citation` is not decorative
  (`REQ-DATA-005`): every generated claim about the user's history MUST be
  traceable to an `Entry.id` — the schema makes that representable here;
  producing citations is spec 017's contract, and detecting ungrounded
  assertions is spec 022's evaluation harness.
- Enums persist as `String`/`Int` raw values (`Codable` value types), never as
  opaque blobs, so CloudKit mirroring and future schema migration stay legible.

**Supporting types (this spec's own contracts):**

```swift
enum CaptureSource: String, Codable, Sendable { case voice, text, suggestion }
enum IndexState:    String, Codable, Sendable { case pending, indexed, excluded }
enum ReflectionKind: String, Codable, Sendable { case entry, weekly, monthly }
enum TurnRole:      String, Codable, Sendable { case user, assistant }
/// Minimal thumbs signal for the §13 quality study; spec 022 may extend it.
enum ReflectionRating: String, Codable, Sendable { case up, down }

/// Coarse by design (REQ-DATA-006): buckets and booleans, never raw samples.
struct HealthSnapshot: Codable, Sendable, Equatable {
    var sleepBucket: SleepBucket?      // bucketed, not minutes
    var workoutOccurred: Bool?         // occurred, not workout details
    var stateOfMindValence: Double?    // −1.0…1.0, only if user logs it in Health
}
enum SleepBucket: String, Codable, Sendable { case underSix, sixToEight, overEight }
```

`TrustZone` is **spec 014 R1's contract** — `.z0Device`,
`.z1AppleContent(reasoningLevel:)`, `.z1AppleContentFree` — persisted `Codable`
on `Reflection.zone` and `Turn.zone` exactly as 014 R1's acceptance criterion
anticipates ("needed for persistence in spec 015's `Reflection.zone` /
`Turn.wasDegraded` fields"). §5.2's inline comment "`.device` or `.apple`" is
shorthand superseded by 014's cases; do not create a second enum.

**Schema gap inherited from the source doc:** `Attachment` is referenced by
`Entry.attachments` but never defined in §5.2. This spec defines the minimal
contract — `@Model final class Attachment { var id: UUID; var kind: String;
var fileAssetID: String? }` — with bytes living as files in the app container
under the same asset-store pattern as audio (R5), never as mirrored blobs.

**`indexState` state machine** (donation itself is spec 016's; the field and
its transitions are this spec's):

```
                donation succeeds (spec 016 pipeline)
   .pending ─────────────────────────────────────────▶ .indexed
      ▲ │                                                 │
      │ │ excludedFromIndex = true (user, per entry)      │ entry edited →
      │ ▼                                                 │ re-donate: back
   .excluded ◀────────────────────────────────────────────┘ to .pending
      │
      └── excludedFromIndex = false → .pending (re-donation queued)
```

`.excluded` is reachable from both other states; leaving it always re-enters
`.pending`, never jumps straight to `.indexed` — the index is only ever trusted
after a fresh donation.

**Swift 6 boundary rule (constrains every downstream spec):** `@Model` classes
are **not `Sendable`** — pass `PersistentIdentifier`/`UUID` across actor
boundaries and re-fetch in the receiving context, never the model object
(`technology/09` §1). Every `IntelligenceService`/background-task signature in
specs 016–019 takes identifiers, not models. `HealthSnapshot`, `TrustZone`, and
all enums above are `Sendable` value types precisely so they can cross freely.

**Acceptance:** schema compiles under Swift 6 complete concurrency; a Swift
Testing suite (`SchemaMirroringComplianceTests`) walks every `@Model` property
via the schema's metadata and asserts the four mirroring constraints
(optional-or-defaulted, no `.unique`, inverses present, raw-value-storable
enums); a `TrustZone` `Codable` round-trip test passes here (discharging 014
R1's acceptance); a fixture test populates the store from spec 013 R4's corpus
(`Fixtures/corpus/entries-*.json` → `Entry` rows) proving the schema fits real
entry shapes. All of this is buildable against the iOS 26 SDK today except the
final iOS 27 recompile — **unblocked** apart from R7's target bump.

### R2. Store configuration and CloudKit private-DB mirroring
`ModelConfiguration(schema:cloudKitDatabase: .private("iCloud.<bundle-id>"))`
into a single `ModelContainer` (`REQ-DATA-001`; `technology/05` §2, 🟡 LIKELY —
stable since iOS 17). Private database only: no public DB, no shared DB, no
custom `CKRecord` schema outside SwiftData's mirroring. **Zone tag:** CloudKit
replication is **Z1** per architecture §3.2 (leaves the device, stays in
Apple's attested infrastructure, encrypted, user's own account). It is not a
`GenerationRequest`, so it carries no `TrustZone` value on a request type —
like WeatherKit in 014 R1, it is classified by 014 R4's `NetworkCallSiteAudit`
in the Apple-infrastructure category (the content-carrying analog of
`.z1AppleContentFree`), and disclosed in the privacy explainer.

**Degradation behavior (required for every Z1 operation, §17):** the device is
the system of record (P2) — every mirroring failure degrades to fully
functional local-only operation, silently for the write path and visibly only
as a passive sync-status line. Nothing user-initiated ever blocks on CloudKit.

**Error taxonomy** (user-facing copy as design copy, not developer strings;
every string reasserts that the journal is safe locally — "sync error" alarm
framing is forbidden):

| Failure | Detection | Copy (draft — design owns final wording) |
|---|---|---|
| No iCloud account / signed out | `CKContainer.accountStatus` | *"Your journal lives on this iPhone. iCloud backup is off — sign in to iCloud to turn it on."* |
| iCloud storage full | `CKError.quotaExceeded` via mirroring | *"iCloud is full, so recent entries aren't backed up yet. Everything is still safe on this iPhone."* |
| Network unavailable | passive | no copy at all — offline is a normal state (`REQ-PLAT-003`), not an error |
| Container fails to init / mirroring stops (schema violates a mirroring rule) | dev-time; the failure is silent per `technology/05` §2 | never user-facing — this is a build defect caught by R1's `SchemaMirroringComplianceTests`, not shippable |

**Field-level encryption (V25, 🔴 UNVERIFIED):** `@Attribute(.allowsCloudEncryption)`
on `Entry.transcript` — the most sensitive mirrored column — is worth having
**if** the mirror supports it. Acceptance explicitly requires verifying current
support against the iOS 27 SDK headers *before* the schema freezes; do not
assume it works, and do not ship a schema that silently drops it.

**Acceptance:** container initializes with the CloudKit configuration in a test
target (mirroring compat proven by R1's suite); Given a device with no iCloud
account, when the app cold-launches, then capture/edit/search all work and the
sync-status line shows the signed-out copy above — no alert, no blocked UI.
Given V25 unresolved, when the schema is finalized, then a recorded verdict
(supported / unsupported, with header citation) exists in this spec first.
Store configuration code is writable today; the V25 check is Xcode-27-gated.

### R3. Data Protection class and app lock
Store file at `NSFileProtectionCompleteUntilFirstUserAuthentication` **minimum**
(`REQ-DATA-003`); `NSFileProtectionComplete` is preferred *iff* §9.6 background
generation (`REQ-SUR-005`, Sunday `BGProcessingTask`) can be scheduled around
unlock — 🔴 UNVERIFIED (V5 / §16 item 10, `technology/05` §4): `.complete` may
make the store unreadable while locked, killing background weekly generation.
The choice is made from a device test, not assumption; if `.complete` blocks
`BGProcessingTask`, either keep `.completeUntilFirstUserAuthentication` or move
generation to next-foreground-launch. Audio files and all container assets (R5,
`Attachment`) get the same protection class applied at the file level.

App lock (`REQ-DATA-004`): optional, **default on**, via `LocalAuthentication`
with `.deviceOwnerAuthentication` — biometrics **with passcode fallback** —
never `.deviceOwnerAuthenticationWithBiometrics`; a user who fails Face ID
three times must not be locked out of their own diary (`technology/05` §5).
Spec 023 R6 already shipped exactly this policy for the existing lock screen —
this spec inherits it unchanged rather than re-deciding. Lock state MUST gate
Spotlight result visibility (§6.5) — the *contract* is stated here; the gating
implementation belongs to spec 016's donation pipeline. All operations in this
block are Z0.

**Acceptance (Given/When/Then):** Given a locked device with `.complete`
protection under test, when the Sunday `BGProcessingTask` fires, then the
observed behavior (store readable or not) is recorded in this spec and in
`technology/11` V5, and the protection class is chosen from that evidence —
Xcode-27 + real-device gated. Given app lock enabled, when the user fails
biometrics, then the device-passcode path succeeds (already verified by 023
R6's acceptance — re-run, don't re-implement). Given app lock enabled and the
device locked, when Spotlight is searched from the system UI, then no journal
content is visible (test lands with spec 016; contract stated here).

### R4. Health integration — coarse, read-only, Z0
`HealthSnapshot` (contract in R1) is written only with explicit HealthKit
authorization, is read-only from Health, and stores coarse values only:
sleep-duration bucket, workout-occurred boolean, `HKStateOfMind` valence if the
user logs it (`REQ-DATA-006`; `technology/08` §3, 🟡). Permission is requested
in context, late (`technology/08` §6 rule 5) — never in onboarding.

Write-back (`REQ-DATA-007`, SHOULD): offer to write the entry's inferred mood
to Health as an `HKStateOfMind` sample — **off by default, one-tap opt-in**.
All Health reads and writes are **Z0** (HealthKit is on-device).

**`DEC-006` — OPEN, do not resolve in this spec:** does HealthKit-derived
context enter Z1 prompts at all (`REQ-DATA-008`)? Health data MUST NOT be sent
to PCC raw under any option; the open question is narrower:
- **Option A — exclude entirely** (source doc's conservative recommendation):
  health context is used only *on-device* to select entries for a reflection,
  and correlations are computed as Z0 statistical operations whose *result*
  (not inputs) informs prose — "flat on six of eight nights under six hours of
  sleep" needs no health data in any prompt. Implies: zero App Review exposure,
  and the Patterns feature works fully; weekly-reflection prose can't directly
  reference sleep/workout context beyond precomputed correlation strings.
- **Option B — Z0-summarized neutral phrase** ("a week with poor sleep")
  included in Z1 prompts. Implies: marginally richer PCC prose, but rests on
  🔴 V7 / §16 item 11 — current App Review guidance on HealthKit data in
  third-party model prompts is unverified, and historically strict. Requires a
  verified answer from Apple before implementation.

The schema is identical under both options (this is why `DEC-006` doesn't block
this spec's schema work); the decision gates spec 017's prompt assembly, and
the routing table there must carry the verdict. Default posture until resolved:
Option A.

**Acceptance:** Given HealthKit authorization denied or never requested, when
an entry saves, then `healthContext == nil` and nothing else differs. Given
authorization granted, when an entry saves, then `HealthSnapshot` contains only
the three coarse fields (a test asserts no other HK-derived value is persisted
anywhere). Given write-back opt-in untouched, when reflections generate, then
no `HKStateOfMind` sample is ever written. `DEC-006` has a recorded resolution
(with the V7 evidence) before spec 017's Z1 prompt assembly is implemented —
not before this spec closes. Schema + read path are **unblocked** today.

### R5. Audio store — files, retention, no default sync
Original audio lives as **files in the app container**, never as SwiftData
blobs (`REQ-DATA-009`) — large binaries in a mirrored store are a sync
disaster (`technology/05` §6). `Entry.audioAssetID` references the file; the
file system holds the bytes; protection class per R3. Format: compressed
AAC/Opus at re-transcription quality — 🔴 UNVERIFIED (V27 / §16 item 15):
codec availability and target file sizes MUST be verified against the SDK and
measured on-device before the write path is implemented, not assumed.

Retention (`REQ-DATA-010`) is a user setting with three values: discard after
transcription, keep 30 days, keep forever.

**`DEC-007` — OPEN, do not resolve in this spec:** is "discard after
transcription" the right *default*?
- **Option A — discard after transcription (source doc's stated default):**
  audio is the highest-sensitivity artifact and the largest storage consumer;
  most users want the words. Implies: minimal storage/privacy surface, but the
  recording is irreversibly gone — no re-transcription after model
  improvements, no voice keepsake, and the choice must be legible at capture
  time, which touches onboarding copy (the §15 table lists onboarding as
  blocked by this decision).
- **Option B — keep 30 days (or keep forever) as default:** preserves
  re-transcription and the voice-artifact value adjacent to the Personal Voice
  differentiator (§8.5). Implies: growing storage, a larger sensitive-data
  surface at rest, and a worse answer to "what does Memento keep?"

The setting's three values ship regardless; only the default is open. Owner of
the resolution: this spec's implementation session together with the
onboarding copy owner (spec 023/018 surface).

CloudKit: audio files MUST NOT sync by default (`REQ-DATA-011`) — optional,
disclosed, **separately toggled** from the store mirror. Zone: capture and
retention are Z0; the optional audio sync, when enabled, is Z1 under the same
classification as R2.

**Acceptance (Given/When/Then):** Given retention = discard-after-transcription,
when transcription completes, then the audio file is deleted and
`audioAssetID == nil` (test asserts the file is gone from disk, not just the
reference). Given retention = 30 days, when the retention sweep runs, then only
files older than 30 days are removed. Given default settings, when entries with
audio sync via CloudKit, then no audio bytes appear in any CKRecord (assert
mirror payload excludes the files). V27 has a recorded codec/size verdict
before the write path lands — Xcode-27-gated; the retention state machine and
file-store layout are designable now.

### R6. Export and five-store deletion
**Export (`REQ-DATA-012`):** full export to **Markdown and JSON**, including
reflections and citations, generated entirely on-device (**Z0**), delivered via
share sheet or Files. Free tier, always (`REQ-MON-003` — never hold a user's
own words hostage; spec 021 owns the tier table, this spec owns the guarantee
that export never checks entitlement). Surfaced as the "Your Data" Export row
(PRES-085 / ATTACH-06 — spec 023 R4 owns the Settings entry point).

**Deletion (`REQ-DATA-013`):** "Delete everything" removes all **five stores**
— (1) SwiftData store, (2) audio files in the container, (3) Core Spotlight
index entries, (4) cached TTS renders (`Reflection.audioAssetID`, §8.5), (5)
CloudKit records — and **reports completion**. This spec extends spec 023 R4's
interim mechanics (`AppStateStore.deleteEverything()`: local storage, Keychain,
UserDefaults, caches) to the five-store scope; 023 keeps the UI entry point and
copy. Partial deletion that leaves Spotlight entries behind is a **P0 privacy
defect** — the user believes the journal is gone while their words sit in a
system index.

**Acceptance (Given/When/Then):**
- Given a populated store (use spec 013 R4's fixture corpus), when the user
  exports, then the Markdown and JSON outputs contain every entry, every
  reflection, and every citation (IDs cross-checked programmatically), and the
  export completes in airplane mode — proving Z0.
- Given entries with audio, cached TTS renders, donated Spotlight items, and
  mirrored CloudKit records, when "Delete everything" completes, then a Swift
  Testing suite (`FiveStoreDeletionTests`, per `technology/05` §8's "write a
  test that asserts all five are empty afterward") asserts: SwiftData fetch
  counts are zero for all entities; the audio/TTS asset directories are empty;
  `CSSearchableIndex` reports no items for the app's identifiers; the CloudKit
  deletion request has been issued and acknowledged (or queued with visible
  pending state when offline — deletion MUST NOT silently skip the mirror).
- Given deletion completes, when the app cold-launches, then it is
  indistinguishable from a fresh install (023 R4's criterion, re-run at the
  five-store scope).
- Given the device is offline mid-deletion, when connectivity returns, then
  the CloudKit leg completes without user re-initiation, and the completion
  report distinguished "deleted locally, iCloud pending" from "everything
  deleted."

Spotlight-leg and TTS-leg assertions land as those stores come into existence
(specs 016/018) — the test scaffold and the local/CloudKit legs are
**unblocked** now.

### R7. Platform baseline — target, concurrency, offline, capability tier
- `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (`REQ-PLAT-001`; currently 17.0 in
  `project.pbxproj`). **Unblocked — Xcode 27 beta installed 2026-07-26** (spec
  013 task 8); the bump is the last mechanical step, not the first, and must be
  verified to build before dependent work proceeds.
- Swift 6 language mode, strict concurrency **complete** (`REQ-PLAT-002`);
  isolation model per `technology/09` §1 (SwiftData `ModelContext`:
  `@MainActor` for UI contexts, background contexts explicit; R1's
  identifier-passing rule is the enforcement mechanism).
- Offline end-to-end (`REQ-PLAT-003`): launch, capture, transcribe, index,
  search, reflect on a single entry, and read aloud with the network fully
  disabled. Only weekly/monthly/chat MAY require connectivity, each with a Z0
  fallback (the fallback contract itself is spec 014 R2 / spec 017).
- Capability tier (`REQ-PLAT-004`): a `CapabilityTier` enum
  (`.full`, `.local`, `.reduced` — `.blocked` is not representable at runtime;
  it is the store-listing floor) resolved at launch and re-resolved on
  `SystemLanguageModel.availability` change, published as observable state.
  The paywall-in-Reduced-tier constraint and `DEC-001` (ship on Reduced at
  all?) are **owned by spec 021** — this spec provides the tier signal, not
  the policy.

**Acceptance:** Given airplane mode from cold launch, when the full §4 loop
runs (capture → transcribe → index → search → entry reflection → read aloud),
then every step completes — manual walkthrough scripted in Verification;
transcription/reflection/TTS legs land with specs 017/018, the
capture/store/search legs are testable when this spec's Phase 1 build exists.
Given a simulated `availability` change, when the tier re-resolves, then
observers see the new tier without relaunch (unit-testable behind a protocol
today; the real `SystemLanguageModel` binding is iOS-27-SDK-gated). Deployment
target and strict-concurrency settings verified by grep on `project.pbxproj`
once the Xcode 27 blocker clears.

### R8. Migration interplay (`REQ-MIG-001`) and Supabase decommission
Spec 023 R5 already shipped the **local-evidence half**: on cold launch,
existing users are recognized from local artifacts (cached name + lock or
entries), onboarding is skipped, Keychain untouched — no network, idempotent,
tested. This spec owns the **remote-pull half** and MUST NOT contradict 023's
implementation: entries that exist only server-side get a one-time, on-device
pull over the still-valid session, re-materialized under their existing UUIDs
into SwiftData, **before** `supabase/` is deleted. Gate: spec 013 R5's
user-count check (a user action, still open). If the real TestFlight user
count is ~zero, the source doc's escape clause applies — **document that here
and skip**; 023 R5's local-only implementation already satisfies that branch
by default. Zone note: the pull is a wind-down read of the user's own data
from the legacy third-party backend — content flows *to* the device, never
up; it is a decommission step outside the 014 zone contract, which governs
the 2.0 steady state, and it must be the last third-party content connection
the app ever makes.

Deletion executes spec 013 R7's verified manifest (32 migrations, 6 edge
functions + `_shared/`, deno CI job, deploy workflows, release-endpoint build
phase, `SUPABASE_*` config keys, `supabase-swift` SPM dependency) — not the
source doc's generic table.

**Acceptance:** a recorded disposition in this spec — either "user count ~zero:
remote pull skipped per `REQ-MIG-001` escape clause" or a tested pull path
(fixture: a synthetic server-side-only entry set, imported once, UUIDs
preserved, second run is a no-op) — exists **before** the `supabase/` deletion
commit. After deletion: `grep -ri "supabase" MeetMemento/ --include="*.swift"`
returns nothing, the SPM dependency is gone, and the app builds and passes
023's regression walkthrough. Unblocked except that the deletion commit itself
waits on spec 013's gate (Spike A pass + DEC-002 resolved) per 013's
Regression Guards.

### R9. §16 verification-queue ownership
This spec owns three §16 items plus one V-queue item, all currently
**outstanding**: item 10 (V5, protection class vs `BGProcessingTask` — R3),
item 11 (V7, HealthKit in model prompts — R4/`DEC-006`), item 15 (V27, audio
codec/file sizes — R5), and V25 (`.allowsCloudEncryption` — R2). Each MUST be
marked confirmed-with-evidence or explicitly outstanding in this spec's
Verification before the spec closes, and mirrored into
`technology/11-verification-queue.md`. All four are Xcode-27-and/or-device
gated; none blocks writing the schema, the deletion scaffold, or the migration
disposition.

## Out of Scope

- Core Spotlight donation itself — spec 016 (this spec only defines `indexState`
  as a field on `Entry`; the donation pipeline is 016's).
- The `IntelligenceService` that populates `title`/`summary`/`moodLabels`/etc. at
  save time — spec 017 (this spec defines the fields; 017 fills them).
- Actual Xcode project changes (deployment target, entitlements) — tracked as a
  task here but the mechanical pbxproj/xcconfig edits happen during this spec's
  execution, not during this specs-authoring pass.

## Tasks
- [ ] 1. Map each pre-2.0 model (`Entry.swift`, `JournalEntry.swift`,
      `ChatSession.swift`, `Insight.swift`/`UserInsight.swift`) to its 2.0
      `@Model` replacement; document what's dropped vs. carried forward. The
      `userId` fields on every pre-2.0 model are **dropped** — there are no
      accounts (spec 023); by the time this spec deletes `supabase/`, no UI
      code calls auth, so the deletion surface here is services and data only.
      The "Delete everything" Settings entry point is owned by spec 023 R4
      (PRES-085); this spec extends its mechanics to the full five-store
      deletion per `REQ-DATA-013`.
- [ ] 2. Define full `@Model` schema per source doc §5.2.
- [ ] 3. Configure `ModelConfiguration` + CloudKit private-DB mirroring
      (`REQ-DATA-001`, `REQ-DATA-002`).
- [ ] 4. Set Data Protection class on the store file (`REQ-DATA-003`) —
      ⚠️ VERIFY item 10 (interaction with `BGProcessingTask` while locked).
- [ ] 5. Implement HealthKit read-only integration + optional write-back
      (`REQ-DATA-006`, `REQ-DATA-007`) — resolve `DEC-006` first;
      ⚠️ VERIFY item 11 (App Review guidance on HealthKit data in prompts).
- [ ] 6. Implement audio store (`REQ-DATA-009`–`011`) — resolve `DEC-007`;
      ⚠️ VERIFY item 15 (codec availability/file sizes).
- [ ] 7. Implement export (`REQ-DATA-012`) and full deletion (`REQ-DATA-013`).
- [ ] 8. Raise `IPHONEOS_DEPLOYMENT_TARGET` to 27.0, enable Swift 6 strict
      concurrency = complete (`REQ-PLAT-001`, `REQ-PLAT-002`).
- [ ] 9. Verify offline operation end-to-end per `REQ-PLAT-003`.
- [ ] 10. Delete `supabase/` per the source doc's §14.1 deletion manifest, as
      cross-checked in spec 013's R7.

## Verification
- [ ] `SchemaMirroringComplianceTests` passes: every `@Model` property is
      optional or defaulted, no `@Attribute(.unique)`, every relationship has
      an inverse, all enums raw-value-storable (R1). Buildable against iOS 26
      SDK now; re-run after the iOS 27 recompile.
- [ ] `TrustZone` `Codable` round-trip test passes here, discharging spec 014
      R1's persistence acceptance (`Reflection.zone` / `Turn.zone`) (R1).
- [ ] Fixture-corpus load test: spec 013 R4's `Fixtures/corpus/entries-*.json`
      materializes into `Entry` rows without loss (R1).
- [ ] Container initializes with `.private` CloudKit configuration; cold launch
      with no iCloud account leaves capture/edit/search fully working with only
      the passive signed-out sync-status copy from R2's error taxonomy (R2).
- [ ] §16 item 10 / V5 — `NSFileProtectionComplete` vs `BGProcessingTask` while
      locked: **outstanding** (Xcode 27 + real device). Device-test verdict
      recorded here and in `technology/11` V5 before the protection class is
      chosen (R3).
- [ ] §16 item 11 / V7 — HealthKit data in third-party model prompts:
      **outstanding**. Blocks `DEC-006` resolution (R4), not this spec's schema;
      verdict must exist before spec 017 assembles any Z1 prompt with health
      context. Until then Option A (exclude entirely) is the operative posture.
- [ ] §16 item 15 / V27 — audio codec availability and target file sizes:
      **outstanding** (Xcode 27 / device measurement). Verdict recorded before
      R5's audio write path is implemented.
- [ ] V25 — `@Attribute(.allowsCloudEncryption)` on `transcript` under CloudKit
      mirroring: **outstanding** (Xcode 27 header check). Supported/unsupported
      verdict recorded before schema freeze (R2).
- [ ] App-lock policy: `.deviceOwnerAuthentication` (passcode fallback) in
      place; 023 R6's lock-screen acceptance re-run unchanged (R3).
- [ ] `HealthSnapshot` coarse-fields test: with authorization granted, only the
      three coarse fields persist; with it denied, `healthContext == nil`; no
      `HKStateOfMind` write occurs without explicit opt-in (R4).
- [ ] Audio retention tests: discard-after-transcription deletes the file from
      disk; 30-day sweep removes only expired files; no audio bytes in any
      mirrored CKRecord under default settings (R5).
- [ ] Export test: Markdown + JSON contain every entry/reflection/citation from
      the fixture store (IDs cross-checked), generated in airplane mode (R6).
- [ ] `FiveStoreDeletionTests` passes: SwiftData, audio files, Spotlight index,
      cached TTS renders, CloudKit all empty (or CloudKit visibly pending when
      offline) after "Delete everything"; post-deletion cold launch is
      indistinguishable from fresh install (R6). Spotlight/TTS legs activate
      with specs 016/018.
- [ ] `grep -n "IPHONEOS_DEPLOYMENT_TARGET" MeetMemento.xcodeproj/project.pbxproj`
      shows 27.0 and strict concurrency = complete is set — **Xcode-27-gated**
      (R7).
- [ ] Airplane-mode walkthrough scripted and run: launch → capture → transcribe
      → index → search → entry reflection → read aloud, network fully disabled
      (R7; transcription/reflection/TTS legs mature with specs 017/018).
- [ ] `CapabilityTier` re-resolution test passes behind a protocol; real
      `SystemLanguageModel.availability` binding re-verified on iOS 27 SDK (R7).
- [ ] `REQ-MIG-001` disposition recorded in this spec (skip-with-documentation
      or tested pull path with preserved UUIDs) **before** the `supabase/`
      deletion commit; after deletion, `grep -ri "supabase" MeetMemento/
      --include="*.swift"` returns nothing and the `supabase-swift` SPM
      dependency is gone (R8).
- [ ] All four R9 verification items mirrored into
      `technology/11-verification-queue.md` with updated markers when resolved.

## Regression Guards
`CONSTITUTION.md` §2 *Security*: PIN/Keychain/encryption/biometrics are unaffected
by this rewrite and MUST still hold after this spec lands. The retired RLS
guarantee's replacement (`REQ-DATA-003`, Data Protection class) must be verified
before this spec can close. `CONSTITUTION.md` §4 rule 2 (SwiftData schema
versioning) and rule 7 (Data Protection / CloudKit re-verify) apply to every task
in this spec. Preservation contract: PRES-020…026 (journal list/editor/local-first
behavior) and PRES-085 ("Your Data" section incl. Delete Everything and the new
Export row, ATTACH-06) must survive the storage swap — the user-visible journal
experience is identical before and after this spec, only the store changes.
