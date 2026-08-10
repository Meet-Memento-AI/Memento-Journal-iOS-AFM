# 12 — Enhancement plan: App Store Connect readiness

**Compiled 2026-08-10.** Full-build review focused on the **data/privacy layer
(“backend”)**, **dark mode**, **accessibility**, and the store-facing defects
that still block Submit for Review.

This plan does **not** replace
[`00-readiness-checklist.md`](00-readiness-checklist.md) (Gate S owner checklist)
or [`specs/ROADMAP.md`](../../specs/ROADMAP.md) (2.0 phase board). It sequences
the **highest-leverage product enhancements** so the *current* on-device binary
can honestly pass App Review, while staying compatible with the Memento 2.0
SwiftData / CloudKit / PCC path.

---

## Verdict

The app is already positioned as **on-device only** (no accounts, no
`URLSession`, Foundation Models intelligence, AES-GCM local journal encryption).
That is the right privacy story for App Store Connect.

What still blocks a clean review is mostly:

1. **Store/legal drift** — live Support URL 404; live privacy policy still names
   OpenAI / Google / Supabase (Guideline **1.5** / **5.1.1** / **5.1.2**).
2. **Backend ghosts in the binary** — pending-sync queues, “sync when you’re
   back” copy, and dead StoreKit/subscription leftovers that contradict the
   no-server product.
3. **Dark mode incomplete** — theme tokens exist, but ~20 screens still paint
   `#FAFAFA` / hardcoded whites that break Appearance → Dark.
4. **Accessibility unfinished** — helpers and many labels exist (~55/156 Swift
   files), but Dynamic Type still has **65** `.system(size:)` call sites and
   primary flows are not VoiceOver-complete end-to-end.

Ship Track A below before Submit. Treat Track B (SwiftData/CloudKit/PCC) as the
post-1.0 / 2.0 foundation — do not block 1.x on iOS 27 GA or PCC entitlement.

---

## Architecture snapshot (what “backend” means today)

| Layer | Current state | App Store implication |
|---|---|---|
| Auth / accounts | Removed (spec 023) | No demo account needed; review notes must say so |
| Journal persistence | `LocalJournalStorage` + `EncryptionService` DEK in Keychain | Honest “Data Not Collected” *if* nothing leaves the device |
| Sync / server | **Gone**, but `PendingSyncOperation`, offline “sync” UI, and `Entry.syncStatus` remain | Misleading UX → Guideline **2.3** (accurate metadata) / **2.1** confusion |
| Intelligence | On-device `IntelligenceService` / Foundation Models | Keep zone disclosure honest; no Z2 content |
| Speech | `requiresOnDeviceRecognition = true` already set | Docs in `03` are stale on this point — update docs, keep the flag |
| Monetization | Dead `SubscriptionPlan` + placeholder `Configuration.storekit` | Noise / inaccurate privacy if left linked |
| 2.0 target | SwiftData + CloudKit private DB (spec 015) — **not in tree yet** | Do not claim CloudKit sync in 1.x store copy |

---

## Track A — Ship 1.x through App Store Connect

Ordered for rejection risk, then product honesty, then polish.

### P0 — Live rejection risks (store + binary honesty)

| ID | Work | Owner | Evidence / acceptance |
|---|---|---|---|
| **A0.1** | Publish `docs/{privacy,terms,support,index}.html` from **this** repo (enable GitHub Pages → `/docs`). Point ASC Privacy + Support URLs at the new host. | ☐ user + agent prep | `curl` → **200** for all four; privacy HTML has **zero** matches for `openai\|supabase\|gemini\|google` AI backend claims |
| **A0.2** | Align in-app links (`AboutSettingsView`, Settings privacy row, `DataUsageInfoView`) + support email to one address (`contact@sebastianmendo.design` per checklist D3). | agent | Single email string; URLs match published host |
| **A0.3** | Set ASC App Privacy nutrition label to **Data Not Collected**, matching `PrivacyInfo.xcprivacy` (empty collected types, `NSPrivacyTracking = false`). | ☐ user | Label ↔ manifest ↔ published policy identical |
| **A0.4** | Close Apple clock items that block upload/sale: PLA, Paid Apps Agreement + tax/banking (if paid), age-rating questionnaire, social-media declaration, EU trader decision. | ☐ user | See checklist §A |
| **A0.5** | Seeded first-run experience so a cold reviewer reaches capture → entry without an empty dead-end (Guideline **2.1**). | agent + ☐ user | Sample content path or explicit review notes; no login wall |

### P0 — Backend / data-layer cleanup (1.x honesty)

Goal: the binary must not behave or speak as if a server still exists.

| ID | Work | Files / surfaces | Acceptance |
|---|---|---|---|
| **A1.1** | **Remove or neutralize pending-sync.** Delete `PendingSyncOperation` queue APIs, or reduce them to no-ops with no UI. Entries are local-only; there is nothing to sync. | `LocalJournalStorage.swift`, `JournalService.swift`, `Entry.swift` (`SyncStatus`), `EntryViewModel.swift`, `JournalCard` pending badge, `YourEntriesView` / `AddEntryView` | No “waiting to sync” badge; no `PendingSync/` directory writes in new installs |
| **A1.2** | **Rewrite offline copy.** Banner currently says entries “sync when you’re back” — false. Either remove the banner (fully local product) or say journaling works offline with no sync claim. | `OfflineBanner.swift`, Insights/AIChat offline empty states | Zero user-visible “sync” / “server” / “connection required for journal” claims |
| **A1.3** | **Delete-everything completeness audit** for the *current* stores: encrypted files, chat store, profile store, Keychain DEK/PIN, UserDefaults, speech/temp caches. Document gaps vs future five-store wipe (spec 015). | `AppStateStore.deleteEverything()`, `LocalChatStore`, `SecurityService` | Manual QA: after wipe, relaunch is fresh-install; no decryptable leftovers |
| **A1.4** | **Strip monetization noise** until `DEC-004` / spec 021 land: placeholder StoreKit product IDs, unused `SubscriptionPlan`, linked-but-unused auth frameworks, orphan `GoogleIcon`, unhandled `memento://` scheme (handle or remove). | checklist C5; `Models/SubscriptionPlan.swift`; `Configuration.storekit` | `check_archive_hygiene.sh` clean; no fake IAP surface in Release |
| **A1.5** | **Stale comment / API cleanup** in chat/journal services that still say “backend”, “server”, “persist feedback”. | `ChatService.swift`, `ChatViewModel.swift`, `EntryViewModel.swift` | Public strings + review-facing copy match on-device model |
| **A1.6** | Keep **`requiresOnDeviceRecognition = true`**; update `docs/app-store/03` which still claims it is unset. Prefer graceful “speech unavailable for this language” UI when on-device ASR is missing. | `SpeechService.swift`, `03-privacy-labels-and-manifest.md` | Doc matches code; denied/unavailable paths are labeled for VoiceOver |

### P1 — Dark mode

Theme infrastructure is solid (`Theme.light` / `Theme.dark`, `ThemeProvider`,
Appearance settings, documented WCAG ratios). The failure mode is **bypass**:
hardcoded light surfaces.

| ID | Work | Evidence (2026-08-10) | Acceptance |
|---|---|---|---|
| **A2.1** | Replace every `Color(hex: "#FAFAFA")` card/chrome fill with `theme.card` / `theme.cardBackground` / `theme.secondary`. | **20** call sites across Settings, Journal, AI Chat, nav chrome | Dark Appearance: no light-gray panels |
| **A2.2** | Sweep hardcoded `Color.white` / `Color.black` / `.foregroundStyle(.white)` outside intentional overlay/on-gradient uses; route through theme tokens. | **~61** hits outside `Theme.swift` (incl. previews) | Side-by-side light/dark screenshots for Journal, Chat, Insights, Settings, Onboarding, Lock |
| **A2.3** | Charts / emotion colors: ensure `PercentageBarChart` hardcoded fills use theme emotion tokens (dark-brightened variants already exist on `Theme`). | `PercentageBarChart.swift` | Legible under dark + Increase Contrast |
| **A2.4** | Verify Liquid Glass / material fallbacks under **Reduce Transparency** and dark mode together (glass on `#FAFAFA` is the common failure). | `GlassEffectCompat` / card backgrounds | AA contrast retained with Reduce Transparency on |
| **A2.5** | App icon: decide whether to ship dark/tinted `AppIcon` variants (currently absent — design TODO in checklist C8). | Assets | Explicit ship/skip decision recorded |

**Suggested implementation order:** shared chrome (`TopNavHeader`,
`DrawerMenuView`, `IconButtonNav`, `AvatarInitialButton`) → Settings cards →
Journal/Chat inputs → charts.

### P1 — Accessibility

Conventions already in tree: `AccessibilityHelpers`, `Typography` +
`relativeTo:`, Reduce Motion on FAB/skeleton patterns, many identifiers
(`welcome.getStarted`, etc.). Finish primary flows for App Review probes.

| ID | Work | Evidence (2026-08-10) | Acceptance |
|---|---|---|---|
| **A3.1** | Dynamic Type: migrate user-readable `.system(size:)` to `Typography` tokens; comment survivors `// icon-size: not user text`. | **65** `.system(size:)` sites | `grep … \| grep -v icon-size` → **0** on user text |
| **A3.2** | AX5 layout pass on: Welcome/onboarding, Add Entry (+ voice), Journal list/detail, AI Chat (+ citations/feedback), Settings leaf screens, Lock/PIN. | Spec 020 R8 / obsolete 008 | No clip/overlap at `.accessibility5`; prefer `minHeight` over fixed frames |
| **A3.3** | VoiceOver completeness on the five primary flows; decorative images `.accessibilityHidden(true)`; cards use `accessibilityCard` / custom actions (edit/delete). | Labels on **~55/156** files | Accessibility Inspector: zero missing descriptions on interactive controls |
| **A3.4** | Voice Control: visible label text matches accessibility labels on primary actions (FAB, tab bar, send, record, delete everything). | Spec 020 `REQ-A11Y-003` | Spoken names activate controls |
| **A3.5** | Reduce Motion audit on remaining springs/typewriter/matched-geometry; follow `FABPressStyle` nil-animation pattern. | 28 `reduceMotion` hits already | Motion off → no decorative animation |
| **A3.6** | Add `#Preview` variants with `.environment(\.dynamicTypeSize, .accessibility5)` and `.preferredColorScheme(.dark)` on reworked screens so drift is visible in canvas. | — | Previews land with the fixes |

### P1 — Privacy / trust UI (still “backend-adjacent”)

| ID | Work | Acceptance |
|---|---|---|
| **A4.1** | `DataUsageInfoView` / About copy: only describe Z0 on-device processing for 1.x; do **not** promise Private Cloud Compute until Z1 ships (checklist B4). | Copy matches binary |
| **A4.2** | Confirm export / delete paths are discoverable (Guideline **5.1.1(v)** spirit even without accounts). | Settings → Delete everything works; review notes mention it |
| **A4.3** | Keep CI gates green: `check_privacy_manifest.sh`, `check_store_metadata.sh`, `check_archive_hygiene.sh`, `check_asc_metadata.sh`. | Required on `main` via branch protection |

### P2 — Product polish that helps review

| ID | Work | Why |
|---|---|---|
| **A5.1** | Empty-state / load flash (`MeetMemento/PLAN.md` race) | Reviewer sees a broken empty journal |
| **A5.2** | Release logging already gated (spec 005) — spot-check no journal text in OS logs | Privacy |
| **A5.3** | Metadata drafts in `docs/app-store/metadata/en-US/` — finalize screenshot set (iPhone 6.9″ + iPad 13″) | Upload requirements |
| **A5.4** | Manual TestFlight path (Gate T) before Submit | Catch Release-only issues |

---

## Track B — 2.0 data layer (not a 1.x Submit blocker)

Do this on the roadmap cadence in `specs/ROADMAP.md`. Calling it out so Track A
cleanup does not paint us into a corner.

| Phase | Spec | Enhancement | Note |
|---|---|---|---|
| 1 | 014 / 023 / 015 | `TrustZone` persistence, SwiftData schema, CloudKit private mirroring, five-store deletion | 015 still blocked on platform decisions; **do not bump deployment target to unreleased iOS 27** for store builds |
| 2 | 016 / 017 | Spotlight retrieval + intelligence boundary / PCC routing | Requires SBP + PCC filings (checklist A3–A4) before claiming Z1 |
| 3–4 | 018–020 | Capture/`SpeechAnalyzer`, surfaces, App Intents, full a11y re-pass on new surfaces | Spec 020 R8 re-runs a11y after 019 lands |
| 5 | 021 / 022 | Monetization + eval study | Resolves `DEC-004` / RevenueCat **V8** before re-adding IAP |

**Rule:** any Track A deletion of sync UI must not re-introduce a custom sync
protocol later — CloudKit mirroring (015) is the only durability path in 2.0.

---

## Recommended execution order (agent sessions)

```
Session 1  A1.1–A1.5   Backend ghosts + offline/monetization honesty
Session 2  A2.1–A2.4   Dark mode token sweep (chrome → settings → journal/chat)
Session 3  A3.1–A3.3   Dynamic Type + VoiceOver primary flows
Session 4  A0.2, A4.*  In-app legal links, data-usage copy, delete/export QA
Session 5  A3.4–A3.6, A5.1  Voice Control / Reduce Motion / empty-state flash
Parallel    A0.1, A0.3–A0.5  User: Pages publish, ASC labels, agreements, screenshots
Gate        Archive → validate → TestFlight (Gate T) → Submit (Gate S)
```

---

## Explicit non-goals for 1.x Submit

- Rebuilding Supabase / edge functions / third-party LLM backends.
- Waiting on Private Cloud Compute entitlement before first Submit (1.x is Z0-only).
- Full App Intents / widgets / Watch (spec 020) — valuable moat, not review blockers.
- Localizing to additional languages (parked; English-only is acceptable for 1.0).

---

## Cross-references

| Concern | Canonical doc |
|---|---|
| Submit checklist | [`00-readiness-checklist.md`](00-readiness-checklist.md) |
| Prior rejections | [`11-rejection-playbook.md`](11-rejection-playbook.md) |
| Privacy triad | [`03-privacy-labels-and-manifest.md`](03-privacy-labels-and-manifest.md) |
| 2.0 phases | [`specs/ROADMAP.md`](../../specs/ROADMAP.md) |
| A11y requirements | [`specs/020-system-integration-and-accessibility.md`](../../specs/020-system-integration-and-accessibility.md) R8 |
| Data layer target | [`specs/015-data-layer-swiftdata-cloudkit.md`](../../specs/015-data-layer-swiftdata-cloudkit.md) |
| No-account UX | [`specs/023-no-account-experience.md`](../../specs/023-no-account-experience.md) |

---

## Evidence appendix (repo scan, 2026-08-10)

| Signal | Count / result |
|---|---|
| Swift files | 156 |
| Files with accessibility modifiers | ~55 |
| `.system(size:)` | 65 |
| `Color(hex: "#FAFAFA")` | 20 |
| Hardcoded white/black (excl. Theme) | ~61 |
| `accessibilityReduceMotion` usages | 28 |
| `import SwiftData` / `@Model` | 0 |
| `URLSession` in app target | 0 |
| Live `…/support.html` | **404** |
| Live `…/privacy.html` | **200**, still mentions OpenAI / Google / Supabase |
| Speech on-device flag | **Present** (`requiresOnDeviceRecognition = true`) |
