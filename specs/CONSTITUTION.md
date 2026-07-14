# CONSTITUTION — Architecture Baseline & Non-Regression Contract

Verified on 2026-07-13 (branch `sync/upstream-main`). This document records what the
review confirmed is **good** — so remediation work doesn't casually break it — plus the
standing rules every future change must follow.

---

## 1. Architecture snapshot

- **App**: SwiftUI, iOS 17.0 deployment target, universal iPhone+iPad
  (iPhone portrait-only). Bundle id `com.sebastianmendo.MeetMemento`, display name
  "Memento", category Lifestyle. ~151 Swift files.
- **Pattern**: MVVM. Entry point `MeetMemento/MeetMementoApp.swift` branches on auth
  state → `LaunchLoadingView` / `LockScreenView` / `WelcomeView` /
  `OnboardingCoordinatorView` / `ContentView` (tabbed root). Route enums in
  `MeetMemento/Models/Routes.swift`.
- **Layers**: `Views/` (29 files: Journal, Insights, Settings, Security, AI-Chat,
  Onboarding, Monetization) · `ViewModels/` (5 core, all `@MainActor`) ·
  `Services/` (12 singletons) · `Components/` (74) · `Models/` (12) ·
  `Utilities`+`Utils`+`Extensions` (12) · `Resources/` (design system:
  `Theme.swift`, `Typography.swift`, fonts Lora/Sora/Manrope).
- **Backend**: Supabase — auth (email OTP + Sign in with Apple), Postgres with
  pgvector RAG (768-dim Gemini embeddings, HNSW index), edge functions in
  `supabase/functions/` (chat, chat-with-entries, chat-feedback, generate-insights,
  new-user-insights, summarize-chat, sync-embedding, `_shared/`).
  LLMs: Gemini 2.5 Flash (chat/summarize/embeddings), OpenAI gpt-4.1-nano (insights).
- **Config**: Supabase URL/key flow from git-ignored
  `MeetMemento/Config/{Debug,Release}.local.xcconfig` (templates provided) →
  build settings → `Info.plist` `$(SUPABASE_URL)`/`$(SUPABASE_ANON_KEY)` →
  `SupabaseService.swift`. The old `SupabaseConfig.swift` mechanism is deprecated.
- **CI**: GitHub Actions on self-hosted runners — `ios-tests.yml` (build+test+coverage),
  `security.yml` (gitleaks, dependency review), `deploy-dev-staging.yml`,
  `deploy-prod.yml` (manual, typed confirmation). SwiftLint + Sonar configured.

## 2. Verified strengths — DO NOT REGRESS

Each item was explicitly verified in the 2026-07-13 review. Any spec whose work
touches one of these must re-verify it before closing (see each spec's
Regression Guards section).

### Security
- **PIN in Keychain**, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  (`MeetMemento/Services/SecurityService.swift:134`), with **constant-time
  comparison** against timing attacks (`SecurityService.swift:171-195`).
- **Entry encryption**: PBKDF2-SHA256 key derivation with Keychain-stored salt
  (`MeetMemento/Services/EncryptionService.swift:26,182`).
- **Biometrics**: FaceID/TouchID via LocalAuthentication with PIN fallback.
- **RLS complete**: all 12 tracked tables have `ENABLE ROW LEVEL SECURITY` with
  per-user `auth.uid() = user_id` policies.
- **ATS enabled**: `NSAllowsArbitraryLoads = false`.

### Store compliance already in place
- `MeetMemento/PrivacyInfo.xcprivacy` is thorough: tracking=false, collected data
  types (User Content, Email, Name, User ID — all AppFunctionality, none Tracking),
  required-reason APIs declared (UserDefaults CA92.1, File Timestamp C617.1,
  System Boot Time 35F9.1).
- Usage strings present: FaceID, Microphone, Speech Recognition.
- Sign in with Apple entitlement + keychain access group in
  `MeetMemento/MeetMemento.entitlements`.
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

### Backend
- Main `chat` function: JSON-schema-constrained LLM output; cited entry ids
  filtered to the retrieved set (`supabase/functions/chat/lib.ts` —
  `filterCitedIdsToAllowed`) so citations can't be fabricated cross-user.
- `chat-feedback` validates message ownership before writes.
- 19 Deno tests cover `chat/lib.ts` pure helpers.
- `match_journal_entries` RPC is `SECURITY INVOKER` → RLS applies to retrieval.

## 3. Reference implementations

When a spec migrates code toward "the right way", these are the in-repo canonical
examples to converge on (do not invent parallel systems):

| Concern | Canonical implementation | Migration spec |
|---------|--------------------------|----------------|
| Text styles / Dynamic Type | `MeetMemento/Resources/Typography.swift` (`Font.custom(_:relativeTo:)`) | 008 |
| Logging | `MeetMemento/Utils/Logger.swift` (`AppLogger`, DEBUG-gated) | 005 |
| Glass surfaces | one system to be chosen in spec 009 (currently two exist) | 009 |
| Local persistence | `MeetMemento/Services/LocalJournalStorage.swift` | 007 |
| Edge-function auth | inline JWT verify pattern in `supabase/functions/chat/index.ts:295-310` | 004 |

## 4. Standing rules

These outlive the specs. Every future change follows them:

1. **No secrets in tracked files.** Credentials live only in git-ignored
   `*.local.xcconfig` (client) and Supabase function env vars (server).
2. **Every schema change is a migration** in `supabase/migrations/` — never ad-hoc
   SQL against prod, never a second migrations directory.
3. **All logging via `AppLogger`** — no raw `print()` in the app target; never log
   user ids, emails, tokens, or entry content.
4. **All user-facing text via `Typography.swift` tokens** — no fixed
   `.system(size:)` for body/label text.
5. **Edge functions verify the caller's JWT** unless the function's header comment
   documents why not AND the deploy config matches.
6. **New features ship with tests**; the coverage gate only ratchets up
   (see specs 006/011).
7. **Schema changes re-verify RLS**: after touching tables/RPCs, confirm per-user
   policies still hold.
8. **Docs**: engineering docs → `docs/`; work-stream specs → `specs/` using the
   template in `specs/README.md`.
