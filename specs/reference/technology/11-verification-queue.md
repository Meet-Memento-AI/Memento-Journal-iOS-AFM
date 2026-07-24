# Verification Queue

Every 🔴 UNVERIFIED item in this library, consolidated. **Work this list before starting the phase that depends on it.**

This library was assembled from WWDC26 session material, Apple documentation, and secondary sources in July 2026. API surfaces in developer beta change. Anything below is a claim that has *not* been confirmed against a compiling SDK.

---

## P0 — Blocking the architecture

### V1. Can Spotlight donation be hidden from system-wide search?

**Blocks:** the entire retrieval architecture, and therefore Phases 1–3.
**Reference:** `03-spotlight-retrieval.md` §8, architecture spec DEC-002.

If journal entries donated to Core Spotlight surface in system-wide search, someone can pick up an unlocked iPhone, type a word, and read a private journal line. Category-ending.

**Test sequence:**
1. Enumerate `SpotlightSearchTool.Configuration.sources` cases in the SDK.
2. Donate to `CSSearchableIndex(name: "memento-entries")` rather than `.default()`. Confirm items do **not** appear in system Spotlight UI on a real device.
3. Confirm `SpotlightSearchTool` can still retrieve from that named index.
4. Check whether the index respects Data Protection / device lock.
5. Check `CSSearchableItemAttributeSet` for any exclude-from-system-UI attribute.

**If negative:** activate Fallback A (opt-in indexing, default off) or Fallback B (hand-rolled SwiftData retrieval tool). Both are specified in `03-spotlight-retrieval.md` §8.

---

## P1 — Calendar dependencies (file in week 1)

### V2. PCC access application — 🟡 process confirmed 2026-07-23, still open to file
**Reference:** `10-monetization-and-privacy.md` §1, §7; spec 013 R5.
Two-step chain, not one: (a) Small Business Program self-serve enrollment
(`developer.apple.com/app-store/small-business-program/enroll/`, eligibility
≤$1M prior-year proceeds or new developer), then (b) a **separate, genuinely
gated** PCC request at `developer.apple.com/contact/request/private-cloud-compute/`.
**Lead time still unknown** — Apple's docs don't state one — this remains the
longest-lead item in the plan. Still open: actually filing both (requires the
account holder's Apple Developer login, not agent-executable).

### V3. Journaling Suggestions entitlement — 🟡 corrected 2026-07-23, likely not a P1 item at all
**Reference:** `08-context-frameworks.md` §2; spec 013 R5.
Research (Apple docs + developer-forum search) did **not** support the
"requires a request to Apple with review lead time" framing this item was
filed under. `com.apple.developer.journal.allow` appears to be a standard
Xcode-addable capability since Xcode 15.1 beta/iOS 17.2 — no discoverable
request-form URL, unlike V2's PCC endpoint. Not ✅ because Apple's entitlement
reference page didn't yield fetchable body content through available
tooling; confirm with one click (Xcode → Signing & Capabilities → search
"Journal") before fully closing. If confirmed, this drops out of P1 entirely
— it was never actually a calendar dependency.

---

## P1 — Changes design if wrong

### V4. Is the PCC daily limit per-app or per-user across apps?
**Reference:** `02-private-cloud-compute.md` §6.
- **Per-app:** `QuotaGovernor` can budget precisely and reserve capacity for Sunday reflections.
- **Per-user:** the governor must be purely reactive; reservation becomes advisory.

The presence of `limitIncreaseSuggestion` pointing at iCloud+ implies per-user. Plan for per-user; confirm.

### V5. `NSFileProtectionComplete` vs `BGProcessingTask`
**Reference:** `05-data-swiftdata-cloudkit.md` §4.
If `.complete` protection makes the SwiftData store unreadable while locked, background weekly generation cannot run and the scheduling design changes. Test explicitly.

### V6. Personal Voice — App Review posture for non-accessibility use
**Reference:** `06-speech-and-audio.md` B3.
Personal Voice was introduced as an accessibility feature. Confirm that use in a journaling app is permitted **before building the flow**. This is a real risk, not a formality — it is the differentiating feature.

### V7. HealthKit data in third-party model prompts
**Reference:** `08-context-frameworks.md` §3, architecture spec DEC-006.
Conservative default is to exclude health data from all Z1 prompts. Verify with Apple whether even a Z0-summarized neutral phrase is acceptable. Note the correlation feature does not require it.

### V8. RevenueCat SDK impact on "Data Not Collected" label
**Reference:** `10-monetization-and-privacy.md` §5.
If it triggers a collection disclosure, evaluate StoreKit 2 direct. The label is worth more than the dashboard.

---

## P2 — API surface confirmation

### V9. `SpotlightSearchTool.Configuration.sources` — full case list
Directly informs V1. `.files` is confirmed; enumerate the rest.

### V10. Tool registration form
Apple samples show both `tools: [tool]` (instance) and `tools: [MyTool.self]` (metatype). Which is canonical?
**Reference:** `01-foundation-models.md` §5.

### V11. `GenerationOptions.ToolCallingMode`
Reported by secondary sources for iOS 27; not seen in Apple sample code. If it exists it matters for the Ask surface — you want the model to *always* search rather than answer from world knowledge.
**Reference:** `01-foundation-models.md` §5.

### V12. `SpotlightSearchTool` registered tool name
Apple's evaluation sample uses `ToolExpectation("searchSpotlight", ...)`. Confirm the exact string — trajectory expectations depend on it.
**Reference:** `04-evaluations.md` §3.

### V13. `quotaUsage.status` — full case list
`.belowLimit(info)` is confirmed. Enumerate the others.
**Reference:** `02-private-cloud-compute.md` §6.

### V14. Evaluations — Sample Generation APIs
Confirmed to exist; signature unknown. Would make a 200-query gold set feasible instead of hand-authoring 40.
**Reference:** `04-evaluations.md` §4.

### V15. `SpeechAnalyzer` / `SpeechTranscriber` exact initializers and result shape
Architecture is confirmed; parameter names are not.
**Reference:** `06-speech-and-audio.md` A1.

### V16. `AssetInventory` API for locale model download and progress
**Reference:** `06-speech-and-audio.md` A2.

### V17. AirPods high-quality recording API and hardware minimum
**Reference:** `06-speech-and-audio.md` A5.

### V18. Any iOS 27 speech synthesis API beyond `AVSpeechSynthesizer`
WWDC26 material reviewed for this library did not surface one. The assumption is that none shipped. If one did — particularly a streaming-capable one — it would change the chat/reflection split in `06-speech-and-audio.md` B1.

### V19. `PrivateCloudComputeLanguageModel` — `Observable` conformance
Used directly in a SwiftUI `body` in Apple's sample, implying conformance. Confirm.
**Reference:** `09-ui-swift6-testing.md` §2.

### V20. App Intents per-intent privacy manifest declarations
Reported for iOS 27. For a journal, every intent should be declared on-device if the mechanism allows.
**Reference:** `07-app-intents-and-surfaces.md` §1.

### V21. App Intents domain schemas — is there a journaling domain?
If not, use the generic entity path.
**Reference:** `07-app-intents-and-surfaces.md` §1.

### V22. View Annotations API
iOS 27 addition mapping views to entities for conversational reference ("summarize this entry"). Investigate after core surfaces ship.

### V23. Liquid Glass second-iteration token names and migration path
**Reference:** `09-ui-swift6-testing.md` §3.

### V24. iOS 27 foldable layout APIs — hinge-state handling in SwiftUI
**Reference:** `09-ui-swift6-testing.md` §3.

### V25. SwiftData `@Attribute(.allowsCloudEncryption)` — current support
Does field-level encryption apply to the transcript field under CloudKit mirroring?
**Reference:** `05-data-swiftdata-cloudkit.md` §2.

### V26. Spotlight index-readiness API
iOS 27 rebuilds the search index on update, which can take days. Is readiness state queryable so Memento can communicate degraded retrieval rather than silently returning nothing?
**Reference:** `03-spotlight-retrieval.md` §12.

### V27. Audio codec availability and target file sizes
**Reference:** `05-data-swiftdata-cloudkit.md` §6.

### V28. AFM 3 Core Advanced — on-device latency on minimum supported hardware
The p50 < 2s target for entry reflection depends on this. Measure with the Xcode 27 Foundation Models instrument on the oldest Apple Intelligence device, not on a current phone.

---

## How to work this list

1. **Download Xcode 27 beta.** Most of P2 resolves in an afternoon of autocomplete and header reading.
2. **Do V1 on a real device**, not the simulator — system Spotlight behavior differs.
3. **File V2 and V3 the same day** you start. They are the only items with external latency.
4. **Update this file as items resolve.** Change 🔴 to ✅ in the source file, delete the entry here, and note the confirmed signature.
5. **Do not delete any Supabase code until V1 is resolved.** The whole rebuild is contingent on it.
