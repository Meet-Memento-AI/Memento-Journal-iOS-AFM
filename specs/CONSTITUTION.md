# CONSTITUTION — Architecture Baseline & Non-Regression Contract

Verified on 2026-07-13 (branch `sync/upstream-main`); architecture snapshot revised
2026-07-23 for the Memento 2.0 rewrite. This document records what the review
confirmed is **good** — so remediation work doesn't casually break it — plus the
standing rules every future change must follow.

**2026-07-23 note:** Memento 2.0 (see
`specs/reference/memento-2.0-architecture-spec.md`) deletes the Supabase/pgvector/
Gemini backend tier described in the pre-2026-07-23 version of this document and
rebuilds on-device. §1 and §4 below reflect the 2.0 target architecture. §2's
*Backend* subsection is retained but marked superseded — it accurately describes the
pre-2.0 app and remains useful context for specs 001–012, several of which are now
themselves marked obsolete (see `ROADMAP.md`).

---

## 1. Architecture snapshot — Memento 2.0 target

Source of truth: `specs/reference/memento-2.0-architecture-spec.md` §3–§4. Specs
013–022 implement this. The companion API-behavior reference for the same Apple
frameworks is `specs/reference/technology/00-INDEX.md` (WWDC26 session notes with
✅ VERIFIED / 🟡 LIKELY / 🔴 UNVERIFIED confidence markers) — read the file(s) a
spec's `tech_refs:` front-matter names before implementing against P1–P7 below.

- **App**: SwiftUI, **iOS 27.0** deployment target (raised from 17.0 —
  `REQ-PLAT-001`, tracked in spec 015), universal iPhone+iPad. Bundle id
  `com.sebastianmendo.MeetMemento`, display name "Memento", category Lifestyle.
  **Swift 6 language mode, strict concurrency checking = complete** (`REQ-PLAT-002`);
  all model-facing services are `actor`-isolated or `@MainActor`.
- **Pattern**: MVVM, unchanged by the rewrite. Entry point
  `MeetMemento/MeetMementoApp.swift`, route enums in `MeetMemento/Models/Routes.swift`
  — both re-verified, not replaced, as specs 013+ land.
- **Data layer**: SwiftData is the **authoritative** system of record
  (`Entry`/`Reflection`/`Citation`/`Conversation`/`Turn` — see
  `specs/reference/memento-2.0-architecture-spec.md` §5.2), mirrored to the
  **CloudKit private database** for replication/durability only. No server-side
  representation of any journal entry, at rest, anywhere (P2). Owned by spec 015.
- **Retrieval**: entries donated to **Core Spotlight**'s semantic index; a
  `SpotlightSearchTool`-equipped `LanguageModelSession` authors its own queries. No
  embedding pipeline, no vector store. Contingent on `DEC-002` (can donation be
  hidden from system-wide search?) resolving favorably in spec 013 — if not,
  `REQ-IDX-007`'s hand-rolled SwiftData-query fallback tool activates instead. Owned
  by spec 016.
- **Intelligence boundary**: exactly one Swift module imports `FoundationModels`
  (P3). Every AI surface calls the `IntelligenceService` protocol; routing between
  on-device (Z0) and Private Cloud Compute (Z1) is table-driven (`REQ-INT-003`), never
  scattered conditionals. Owned by spec 017.
- **Capture/voice**: `SpeechAnalyzer`/`SpeechTranscriber` for on-device transcription,
  no cloud fallback of any kind (`REQ-CAP-001` — note: the source document's "Gemini
  Audio fallback" concern doesn't apply to this codebase; `SpeechService.swift`
  already has no such fallback to remove, confirmed by spec 018);
  `AVSpeechSynthesizer` (+ optional Personal Voice) for reflection playback. Owned by
  spec 018.
- **Config / identity**: **no accounts at all** (2026-07-23 decision, spec 023 —
  supersedes the earlier "Sign in with Apple only" plan and makes the "No
  account." positioning claim literal). Identity is a locally stored display
  name collected in onboarding; the onboarding-complete gate is a local flag; no
  Supabase URL/key xcconfig flow. CloudKit container entitlement replaces the
  Supabase project (CloudKit uses the device's iCloud account transparently —
  that is Apple's infrastructure, not an app account). Exact
  xcconfig/entitlement changes are execution work tracked in specs 023/015.
- **CI**: GitHub Actions on self-hosted runners — merge lanes are
  `ios-build-online.yml`, `security.yml`, and `spec-gates.yml` (spec 025).
  Optional non-blocking `ios-device-eval.yml` covers live FM generation /
  spikes. No backend deploy workflows for the on-device product.

**Pre-2.0 snapshot (historical, superseded):** see §2 *Backend* subsection below —
SwiftUI/iOS 17.0, Supabase auth + Postgres/pgvector RAG (768-dim Gemini embeddings),
edge functions, Gemini 2.5 Flash + OpenAI gpt-4.1-nano. Accurate as of 2026-07-13;
no longer the target architecture.

## 2. Verified strengths — DO NOT REGRESS

Each item was explicitly verified in the 2026-07-13 review. Any spec whose work
touches one of these must re-verify it before closing (see each spec's
Regression Guards section).

**Incorporated by reference (2026-07-23):** the entire live front-end — shell,
navigation, journal, chat (end-state), onboarding, lock, settings, and design
system — is under the same DO-NOT-REGRESS protection via
`specs/reference/frontend-preservation-contract.md` (`PRES-nnn` IDs). Specs that
rebuild any of it cite the PRES- IDs they touch in their Regression Guards; the
only sanctioned changes are account removal (spec 023) and the contract's own
`ATTACH` map amendments.

### Security
- **PIN in Keychain**, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  (`MeetMemento/Services/SecurityService.swift:134`), with **constant-time
  comparison** against timing attacks (`SecurityService.swift:171-195`).
- **Entry encryption**: PBKDF2-SHA256 key derivation with Keychain-stored salt
  (`MeetMemento/Services/EncryptionService.swift:26,182`).
- **Biometrics**: FaceID/TouchID via LocalAuthentication with PIN fallback.
- ~~**RLS complete**: all 12 tracked tables have `ENABLE ROW LEVEL SECURITY` with
  per-user `auth.uid() = user_id` policies.~~ **Superseded** — Postgres RLS is
  meaningless once the tables it protected are deleted (Phase 1). Its 2.0
  replacement is `REQ-DATA-003` (SwiftData store file MUST use
  `NSFileProtectionCompleteUntilFirstUserAuthentication` at minimum) — owned by
  spec 015, not yet verified.
- **ATS enabled**: `NSAllowsArbitraryLoads = false`.

### Store compliance already in place
- `MeetMemento/PrivacyInfo.xcprivacy` is thorough: tracking=false, collected data
  types (User Content, Email, Name, User ID — all AppFunctionality, none Tracking),
  required-reason APIs declared (UserDefaults CA92.1, File Timestamp C617.1,
  System Boot Time 35F9.1). **Stale for 2.0**: the "collected data types" list
  describes data collected by the Supabase backend being deleted. The 2.0 target
  privacy label is **"Data Not Collected"** (`REQ-MON-004`, contingent on
  RevenueCat's SDK not triggering a collection disclosure). Owned by spec 021 —
  do not hand-edit `.xcprivacy` as part of this specs-only pass.
- Usage strings present: FaceID, Microphone, Speech Recognition.
- ~~Sign in with Apple entitlement~~ + keychain access group in
  `MeetMemento/MeetMemento.entitlements`. **The SIWA entitlement is removed by
  spec 023** (no accounts); the keychain access group stays — PIN/encryption
  keys live there and are account-independent.
- Hosted legal pages linked in-app: privacy (`SettingsView.swift`) and terms
  (`AboutSettingsView.swift`) at `sebmendo1.github.io/MeetMemento/`.
- Automatic signing with real team (F3NM4HTMW8); `LaunchScreen.storyboard` wired.

### Code quality
- **Zero** `fatalError`, `try!`, or `as!` in the codebase.
- All 5 `Timer.scheduledTimer` sites have matching `invalidate()`;
  `[weak self]` used in service closures; `VideoBackground` cleans up its
  `AVPlayer` in `deinit`.
- All core view models are `@MainActor`; errors propagate via `async throws`
  with `.alert`-based surfacing.
- Reduce-motion respected in 8 animation-heavy components.
- Accessibility labels on 39/151 files (67 `accessibilityLabel`, 19 hints,
  12 traits) via shared `MeetMemento/Utilities/AccessibilityHelpers.swift`.
- Retry-with-backoff on network calls in `JournalService` and `ChatService`.
- Bundle media modest (`Resources/welcome-bg.mp4` ≈ 2.5 MB).

### Backend (superseded — historical record of the pre-2.0 app, 2026-07-13)
- Main `chat` function: JSON-schema-constrained LLM output; cited entry ids
  filtered to the retrieved set (`supabase/functions/chat/lib.ts` —
  `filterCitedIdsToAllowed`) so citations can't be fabricated cross-user.
- `chat-feedback` validates message ownership before writes.
- 19 Deno tests cover `chat/lib.ts` pure helpers.
- `match_journal_entries` RPC is `SECURITY INVOKER` → RLS applies to retrieval.

None of the above exists post-2.0 (the entire `supabase/functions/` tree is deleted
in Phase 1). The guarantee this subsection protected — "a citation can't be
fabricated or leaked cross-user" — carries forward as `REQ-DATA-005` (every
generated claim MUST be traceable to an `Entry.id`), owned by spec 015, and MUST be
re-verified against the new `Citation` SwiftData entity before it can be considered
DO-NOT-REGRESS again.

## 3. Reference implementations

When a spec migrates code toward "the right way", these are the in-repo canonical
examples to converge on (do not invent parallel systems):

| Concern | Canonical implementation | Migration spec |
|---------|--------------------------|----------------|
| Text styles / Dynamic Type | `MeetMemento/Resources/Typography.swift` (`Font.custom(_:relativeTo:)`) | ~~008~~ — **superseded**, merged into 020 |
| Logging | `MeetMemento/Utils/Logger.swift` (`AppLogger`, DEBUG-gated) | 005 |
| Glass surfaces | one system to be chosen in spec 009 (currently two exist) | 009 |
| ~~Local persistence~~ | ~~`MeetMemento/Services/LocalJournalStorage.swift`~~ | ~~007~~ — **superseded**, spec 007 obsolete (see 015) |
| ~~Edge-function auth~~ | ~~inline JWT verify pattern in `supabase/functions/chat/index.ts:295-310`~~ | ~~004~~ — **superseded**, spec 004 retired |

New canonical patterns for SwiftData persistence, Core Spotlight donation, and the
`IntelligenceService` boundary will be added to this table as specs 013–022 land and
produce real code to converge on — deliberately left unfilled here rather than
pointing at code that doesn't exist yet.

## 4. Standing rules

These outlive the specs. Every future change follows them:

1. **No secrets in tracked files.** Credentials live only in git-ignored
   `*.local.xcconfig` (client). *(Supabase function env vars apply only until Phase
   1 deletes `supabase/`; not re-added for the 2.0 stack, which has no server.)*
2. **Every schema change is a migration.** Pre-2.0: `supabase/migrations/`, never
   ad-hoc SQL against prod. **2.0 (spec 015):** every SwiftData `@Model` schema
   change ships as a versioned `SchemaMigrationPlan` stage, never an in-place
   property change on a shipped model.
3. **All logging via `AppLogger`** — no raw `print()` in the app target; never log
   user ids, emails, tokens, or entry content.
4. **All user-facing text via `Typography.swift` tokens** — no fixed
   `.system(size:)` for body/label text. **2.0 addition:** any text bound for TTS
   playback (`Reflection.body`, `.observation`) additionally follows `REQ-VOX-006`
   — no markdown, bullet markers, headings, or emoji; enforced by a
   `SpeakabilityLinter` in tests (spec 018).
5. **Exactly one Swift module imports `FoundationModels`** (`REQ-INT-001`, P3).
   Every other module depends on the `IntelligenceService` protocol. *(Replaces the
   pre-2.0 rule "edge functions verify the caller's JWT," which no longer applies —
   there are no edge functions.)* Corollary: **no hardcoded model context budgets**
   — the window is 4096/8192/32768 depending on device and zone; read
   `SystemLanguageModel().contextSize` at runtime and size retrieved-entry
   payloads against it (`technology/01` §3). Owned by spec 017.
6. **New features ship with tests**; the coverage gate only ratchets up
   (see specs 006/011).
7. **Schema changes re-verify Data Protection & CloudKit compatibility**: after
   touching a SwiftData model, confirm the store file's `NSFileProtection` class
   still holds (`REQ-DATA-003`) and every property remains CloudKit-mirroring
   compatible (`REQ-DATA-002` — optionals/defaults, no `.unique`, inverse
   relationships). *(Replaces the pre-2.0 "re-verify RLS" rule — there is no
   Postgres to apply RLS to.)*
8. **No journal content, transcript, derived reflection, embedding, tag, mood
   value, or content-derived metadata may cross into Z2 (third-party) under any
   configuration** (`REQ-PRIV-001`). Every generation surface declares its zone in
   code and renders it in the UI at the point of use (`REQ-PRIV-002`). Owned by
   spec 014.
9. **Docs**: engineering docs → `docs/`; work-stream specs → `specs/` using the
   template in `specs/README.md`; the Memento 2.0 source document lives at
   `specs/reference/memento-2.0-architecture-spec.md` and is cited by `REQ-`/`DEC-`
   ID from the specs that derive from it; the front-end non-regression contract
   lives at `specs/reference/frontend-preservation-contract.md` and is cited by
   `PRES-` ID.
10. **The technology library is the API-truth layer.** Apple-framework claims in
    `specs/reference/technology/` carry confidence markers (✅ VERIFIED /
    🟡 LIKELY / 🔴 UNVERIFIED) — respect them: never write code against a 🔴
    claim without confirming it against the SDK first, and update the marker
    (plus `technology/11-verification-queue.md`) when an item resolves. Several
    of these APIs shipped at WWDC26 and behave differently from anything in a
    model's pre-2026 training data — when the library and an agent's prior
    knowledge disagree, the library wins.
