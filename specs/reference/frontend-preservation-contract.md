# Front-End Preservation Contract

**Document type:** Non-regression contract for the existing SwiftUI front-end
across the Memento 2.0 rewrite
**Companion to:** `memento-2.0-architecture-spec.md` (what gets built) — this
document is what must *not* be lost while building it
**Derived from:** full code audit of `MeetMemento/` on 2026-07-23 (branch
`sync/upstream-main`)
**Cited by:** `PRES-nnn` IDs from specs 013–023 (`pres_refs` front-matter and
Regression Guards sections)
**Status:** Ratified by spec 023 R7

---

## 1. Scope and enforcement

Every behavior in §2 exists in the shipping front-end today and MUST exist,
functionally intact, in the completed 2.0 app — with account creation as the sole
sanctioned removal (spec 023) and the third-tab Patterns mount as the sole
sanctioned shell amendment (§3). Backing services change wholesale
(Supabase → SwiftData/`IntelligenceService`); the user-facing behavior does not,
unless a 2.0 spec explicitly upgrades it (e.g. citations gain tap-through to the
cited entry per spec 019).

Two invariant classes, because the rewrite has a dark period:

| Class | Behaviors | Enforcement window |
|---|---|---|
| **Continuously live** | Shell, journal, editor, onboarding, lock, settings, design system (§2.1–§2.2, §2.4–§2.7) | Must never break at any point during Phases 1–5. Every spec touching them re-verifies before closing. |
| **End-state** | Chat/Ask surface behaviors (§2.3) | Necessarily dark between Phase 1 (edge functions deleted, spec 015) and spec 019 (rebuilt on `IntelligenceService`). Must be **restored intact**; verified at spec 019's close. |

Deprecated/orphaned code is explicitly **not** contract — it is inventoried in
§4's reuse ledger so valuable components get claimed by 2.0 specs instead of
being either accidentally preserved or thoughtlessly deleted.

Line numbers rot; file paths are the durable pointer. Re-verify against code
before relying on a row.

---

## 2. PRES inventory

### 2.1 Shell and navigation

| ID | Behavior | Implementation |
|---|---|---|
| PRES-001 | Root state machine: launch → lock (if configured) → welcome (first run) → onboarding → main content; theme-aware launch background prevents light/dark flash | `MeetMementoApp.swift` (auth branching removed by spec 023 R1) |
| PRES-002 | Slide-out drawer, 280pt: interactive left-edge swipe (40pt zone), tap-outside-to-close, spring animation, content slides right with corner radius + shadow | `ContentView.swift`, `Components/Navigation/DrawerMenuView.swift` |
| PRES-003 | Drawer contents: "About yourself" and "Your journal goals" menu items + Settings capsule button at bottom | `DrawerMenuView.swift`, `DrawerMenuItem.swift` |
| PRES-004 | Two-tab swipeable pill nav (Journal \| Insights/Chat) with `matchedGeometryEffect` sliding glass pill and swipe-progress haptics — **amended to three tabs by ATTACH-03** | `Components/Navigation/TopTabNav.swift` (`TopNav`, `SwipeableTabView`) |
| PRES-005 | Floating top header: avatar-initial button (left, opens drawer), pill nav (center), context action (right: search on Journal, compose/summarize on Chat) | `Components/Navigation/TopNavHeader.swift`, `Components/Buttons/AvatarInitialButton.swift` |
| PRES-006 | Avatar initial renders first letter of locally stored display name, `person.fill` fallback | `AvatarInitialButton.swift`; name from local cache (spec 023 R2) |
| PRES-007 | Floating new-entry FAB on Journal tab: Liquid Glass, hidden when entry list is empty or mid-tab-swipe, positioned above content | `Components/Buttons/NewEntryFAB.swift` (`PositionedNewEntryFAB`) |
| PRES-008 | Full-screen journal search overlay: `SearchTextField` + cancel, empty-prompt state, no-results state, result cards | `Views/Journal/JournalSearchView.swift`, `Cards/SearchResultCard.swift` |
| PRES-009 | "Entry saved" toast on save | `Components/Toast/JournalToast.swift` |
| PRES-010 | Offline banner: dismissible, non-blocking, appears when connectivity drops; journal reads/writes keep working locally | `Components/OfflineBanner.swift`, `NetworkMonitor` (2.0: offline is the *native* state per `REQ-PLAT-003`; the banner's scope shrinks to Z1-only features) |
| PRES-011 | Route enums drive all navigation (`EntryRoute` create/createWithTitle/createWithContent/edit, `SettingsRoute`, `DrawerRoute`) — preserved as the deep-link surface for widgets/App Intents (ATTACH-09) | `Models/Routes.swift` |

### 2.2 Journal

| ID | Behavior | Implementation |
|---|---|---|
| PRES-020 | Entry list with four states: loading spinner, error + Try Again, empty ("No journal entries yet" + create CTA), content grouped in month-header sections | `Views/Journal/YourEntriesView.swift` |
| PRES-021 | Entry cards: title/excerpt/date, pending-sync badge, tap-to-edit, delete via confirmation dialog ("This action cannot be undone") | `Cards/JournalCard.swift` |
| PRES-022 | Month-picker sheet (wheel month+year) synced to scroll position | `Views/Journal/JournalView.swift` |
| PRES-023 | Notion-style full-page editor: drag handle, back, date pill, title field ("Journal title" placeholder), spacious body editor, submit arrow disabled when body empty, keyboard-aware padding | `Views/Journal/AddEntryView.swift` |
| PRES-024 | Editor voice-dictation FAB: expands to live duration display, red stop state, mic-permission and recording-failed alerts | `AddEntryView.swift` + speech service (2.0: `SpeechAnalyzer`, spec 018) |
| PRES-025 | Local-first entry writes with pending-sync indicator and automatic drain on reconnect/foreground | `EntryViewModel`, `LocalJournalStorage` (2.0: SwiftData is authoritative — "pending sync" becomes CloudKit mirror state, spec 015) |
| PRES-026 | Local entry search (title + content filter) | `EntryViewModel.searchEntries` (2.0: may route through Spotlight, spec 016 — behavior preserved either way) |

### 2.3 Chat / Ask (end-state class — restored by spec 019)

| ID | Behavior | Implementation |
|---|---|---|
| PRES-040 | Empty state: Memento glyph, personalized welcome ("Welcome {name}…"), horizontally scrolling suggestion cards rotated from local `AISuggestionPrompts.json` | `Views/AI-Chat/AIChatView.swift`, `AISuggestionCard` |
| PRES-041 | Three-state input field: default (history pill + "Chat with Memento" pill + voice pill) / text-active (1–5 line expanding field + send) / voice-active (inline listening panel: cancel/confirm, audio-reactive dots, transcription auto-send) | `Components/AIChat/ChatInputField.swift`, `AIChatFooter.swift` |
| PRES-042 | Message rendering: user bubbles right-aligned; AI responses full-width with typewriter reveal (~120 cps), heading/body structure, markdown-safe parsing, JSON never shown raw | `ChatMessageBubble.swift`, `AIOutputComponent.swift`, `RichTextParser.swift` |
| PRES-043 | Response action bar: copy, thumbs up, thumbs down (persisted), regenerate | `AIOutputComponent.swift` (2.0: feedback feeds `Reflection.userRating`/eval, spec 022) |
| PRES-044 | Citations: "N journals" tag on grounded responses → bottom sheet with citation timeline (date tags, tappable items) | `CitationLink.swift`, `CitationsBottomSheet.swift`, `CitationTimelineList` (2.0 upgrade: tap-through to the cited entry, spec 019) |
| PRES-045 | Chat history: sheet with drag handle, New-chat button, loading/empty states, sessions titled by first message with relative dates, tap-to-load, swipe-to-delete | `ChatHistorySheet.swift`, `ChatHistoryList.swift`, `ChatHistoryItem.swift` (2.0: `Conversation`/`Turn` entities, spec 015) |
| PRES-046 | Summarize-chat-to-entry: sheet offer → generated summary prefills the entry editor | `ChatSummarySheet.swift` → `AddEntryView` (2.0: Z0 summarization via `IntelligenceService`) |
| PRES-047 | Failure handling: per-message "Failed to send · Retry" row, error alert with Retry, typing indicator during generation | `ChatMessageBubble.swift`, `AILoadingState.swift` |
| PRES-048 | Honest gating states: offline empty state ("needs a connection" — 2.0: only for Z1 with Z0 degradation per `REQ-INT-009`) and AI-disabled state with Enable action (`PreferencesService.aiEnabled`) | `AIChatView.swift` |

### 2.4 Onboarding (account step removed by spec 023)

| ID | Behavior | Implementation |
|---|---|---|
| PRES-060 | Welcome: looping video background with progressive blur + staged dissolve, logo, headline — auth buttons replaced by single "Get Started" (spec 023 R2) | `Views/Onboarding/WelcomeView.swift`, `Components/VideoBackground.swift` |
| PRES-061 | Step order: YourName → LearnAboutYourself → ThemeConfirmation → app-lock setup → LoadingStateView; back from first step returns to Welcome | `OnboardingCoordinatorView.swift` |
| PRES-062 | Name collection (first + last, continue gated on both) populates the local display name | `YourNameView.swift` |
| PRES-063 | "Learn about yourself" free-text step with voice-dictation FAB and live duration; the text becomes the user's **first journal entry** and seeds Experience Profile estimation | `LearnAboutYourselfView.swift` |
| PRES-064 | Themes: AFM/keyword-suggested ThemeCatalog chips (1–6), browse-all by family; editable later from the drawer with Rebuild lens | `ThemeConfirmationView.swift`, `EditJournalGoalsView.swift` |
| PRES-065 | App-lock setup: Face ID offer → PIN alternative (4-box entry, confirm step with shake-on-mismatch) — 2.0: default-on with explicit-friction skip (spec 023 R3) | `FaceIDView.swift`, `SetupPinView.swift`, `ConfirmPinView.swift` |
| PRES-066 | Completion: animated progress ring, phased status messages, rotating tip cards | `LoadingStateView.swift`, `Components/Loading/*` |

### 2.5 Lock

| ID | Behavior | Implementation |
|---|---|---|
| PRES-070 | Lock screen: launch-matching background + icon; biometric auto-trigger on appear; 4-box PIN entry (hidden field, tap-to-focus, auto-validate, shake + "Incorrect PIN", success haptic) | `Views/Security/LockScreenView.swift` |
| PRES-071 | Method switching: "Use PIN"/"Use {biometric}" cross-switch; biometric retry button after failures | `LockScreenView.swift` |
| PRES-072 | Escape hatch: emergency sign-out **replaced** by device-passcode fallback (`.deviceOwnerAuthentication`, spec 023 R6) | `LockScreenViewModel`, `SecurityService` |
| PRES-073 | Auto-lock on background/inactive scene phase; activity timestamp on active | `MeetMementoApp.swift`, `SecurityService` |
| PRES-074 | PIN stored in Keychain with constant-time comparison; entry encryption key derived from PIN + Keychain salt (account-independent — survives spec 023 untouched) | `SecurityService.swift`, `EncryptionService.swift` (CONSTITUTION §2 Security) |

### 2.6 Settings and drawer editors

| ID | Behavior | Implementation |
|---|---|---|
| PRES-080 | Appearance: System/Light/Dark theme picker with icons, descriptions, checkmark; persisted; live theme change | `AppearanceSettingsView.swift`, `PreferencesService` |
| PRES-081 | About: version (tap-to-copy) + device info, Contact Support (mailto), Terms link, Rate on App Store, Share App sheet | `AboutSettingsView.swift` |
| PRES-082 | AI Features toggle with reactive subtitle — 2.0: this *is* the Z0-pin/generative-off control surface (`REQ-INT-004`, spec 017) | `SettingsView.swift`, `PreferencesService.aiEnabled` |
| PRES-083 | Data-usage transparency sheet — content rewritten for 2.0 (no Gemini/Supabase; zone language per spec 014) but the *surface* persists | `DataUsageInfoView.swift` |
| PRES-084 | Profile name edit (≤50 chars, save feedback) against the local cache | `ProfileSettingsView.swift` |
| PRES-085 | Sections merged into one "Your Data" section: profile, AI toggle, privacy policy, data-usage sheet, export (new, spec 015), Delete Everything (spec 023 R4). Sign Out removed | `SettingsView.swift` |
| PRES-086 | Drawer editors: "About yourself" (personalization text, voice FAB, 100-char minimum counter) and "Your journal goals" (re-select chips) — both against local storage | `EditAboutYourselfView.swift`, `EditJournalGoalsView.swift` |

### 2.7 Design system

| ID | Behavior | Implementation |
|---|---|---|
| PRES-090 | Token system: gray/primary scales, full semantic palette with documented WCAG AA/AAA ratios, emotion colors (dark-mode brightened), gradients, radius scale, glass tokens | `Resources/Theme.swift` (CONSTITUTION §3 canonical) |
| PRES-091 | Typography: Manrope (UI) + Lora serif (onboarding), h1–h6/body/caption scale, Dynamic Type via `relativeTo:`/`ScaledMetric` with accessibility cap | `Resources/Typography.swift` (CONSTITUTION §3 canonical) |
| PRES-092 | ~~Liquid Glass surfaces render as one system~~ **(amended 2026-08-07, spec 024):** Liquid Glass was **removed entirely** — it rendered poorly / doubled. Every former glass surface is now a flat `#fafafa` fill (`Color(hex: "#FAFAFA")`); prominent brand actions (new-entry FAB, submit, active-chat action) keep their purple fill. No `.glassEffect` / `.buttonStyle(.glass*)` / `GlassEffectContainer` anywhere. `theme.glassFill` removed; `theme.glassBorder` kept for non-glass insight-card strokes. | view files (`Components/`, `Views/`); tokens in `Resources/Theme.swift` |
| PRES-093 | Haptic vocabulary: impact on taps/tabs/record, notification haptics on success/error — pervasive, part of the product feel (`REQ-SYS-014` extends this) | throughout Views/Components |
| PRES-094 | Motion: spring animations, matched-geometry pill/FAB transitions, typewriter reveals, progressive blur + scroll-edge fades — all respecting Reduce Motion | `ProgressiveBlurHeaderWrapper`, `ScrollEdgeFade`, component-level |
| PRES-095 | Loading affordances: shimmer skeletons, modern progress ring, rotating tip cards | `Components/Data/SkeletonView.swift`, `Components/Loading/*` |

---

## 3. ATTACH map — where 2.0 surfaces mount on the preserved shell

| ID | 2.0 surface | Mount point | Must respect | Owning spec |
|---|---|---|---|---|
| ATTACH-01 | Ask (chat over history) | Replaces the "Insights" tab's *backing service*; the surface itself is the restored §2.3 chat UI | PRES-040…048 in full | 019 |
| ATTACH-02 | Weekly reflection | Card at top of the Journal timeline + the single "weekly reflection ready" notification; listenable per spec 018 | PRES-020, PRES-009 | 019 |
| ATTACH-03 | Patterns / Monthly | **Third pill tab** (Journal \| Chat \| Patterns) — the one sanctioned amendment to PRES-004, decided 2026-07-23; evaluate §4 reuse-ledger chart components first | PRES-004 (amended), PRES-005 | 019 |
| ATTACH-04 | Entry reflection (Z0, at save) | Entry detail/editor surface — title/summary/mood/topics appear on the saved entry; observation only when salience warrants | PRES-021, PRES-023 | 019 |
| ATTACH-05 | TTS narrate / Personal Voice | Reflection surfaces (weekly/monthly/entry) — never chat; reuse ledger `NarrateButton`/`ListeningPanel` as starting points | PRES-093, PRES-094 | 018 |
| ATTACH-06 | Export (Markdown/JSON) | "Your Data" settings row | PRES-085 | 015 |
| ATTACH-07 | Paywall (new — no monetization UI exists today) | Gates reflections/patterns/ask/Personal Voice per `REQ-MON-003`; never gates capture/timeline/search/export | PRES-085, free-tier surfaces untouched | 021 |
| ATTACH-08 | Notification preferences (new) | Settings — exactly two notifications exist (opt-in daily reminder, weekly-ready) | PRES-085 | 019/020 |
| ATTACH-09 | Widgets / Controls / App Intents / Live Activity | Deep-link through the existing route enums (`EntryRoute.create`, etc.); recording Live Activity pairs with the dictation FAB durability contract | PRES-011, PRES-024 | 020 |
| ATTACH-10 | Journaling Suggestions picker | Composer (editor) as a seeded prompt + attachment | PRES-023 | 018 |
| ATTACH-11 | Trust-zone indicator (P4: boundary as UI element) | Generated-content surfaces (reflection cards, chat responses) — new, from spec 014's reusable component | PRES-042, PRES-090 | 014/019 |

## 4. Reuse ledger — deprecated/orphaned code worth claiming

Not contract. Each row is either claimed by a 2.0 spec or deleted during that
spec's rebuild — no third option (unclaimed zombie code violates spec 001's
hygiene standard).

| Component(s) | State today | Claim candidate | For |
|---|---|---|---|
| `InsightsView` + `InsightsContentView` (typewriter headline, staggered reveal, month cache), `SentimentAnalysisCard`, `PercentageBarChart` (WCAG-AAA emotion tokens), `KeywordsCard`, `FollowUpQuestionGroup`, `InsightMonthPickerSheet`, `EntriesTag` | Deprecated — chart-based Insights, off main nav | **Spec 019 Patterns** — this is a substantially built starting point for the Patterns tab (ATTACH-03); `FollowUpQuestionGroup`'s tap-to-create-entry flow is directly reusable | Patterns/Monthly |
| `NarrateButton`, `ListeningPanel` | Orphaned (ChatInputField grew its own inline panel) | **Spec 018 TTS** — playback affordance starting points | Voice output |
| `JournalReviewIndicator` ("Reviewed N journals") | Orphaned | Spec 019 Ask — candidate retrieval-transparency affordance (`REQ-SUR-003`'s "show what it searched") | Ask |
| `MonthlyInsightCard`, `AISummarySection`, `SummaryCard`, `InsightCard` | Orphaned | Spec 019 Weekly/Monthly card design references, else delete | Weekly card |
| `InlineCitationBadge`, `CitationPopover`, `CitationFlowText` | Orphaned (sheet-based citations won) | Delete unless spec 019's inline-citation rendering (`REQ-SUR` citations "rendered inline") revives them | Ask citations |
| `WordCounterNavButton`, `ChatEmptyState`, `InsightAnnotationsSection`, `InsightDateTag`, theme-tag family (`ThemeSection`/`ThemeTag`/`OnboardingThemeTag`, `InsightsThemesSection`), `BottomTab`/`BottomTabsNav`, `TopNav` `.single` variants | Orphaned | Delete during the owning area's rebuild | — |
| `OTPTextField` | Live only in the deleted email-OTP path | Delete with spec 023 R1 (PIN boxes are bespoke, not this component) | — |
| `Configuration.storekit`, `SubscriptionPlan.swift` | Present, unwired | Spec 021 builds monetization new; evaluate then | Paywall |

---

*End of contract. Amendments require a dated note here plus the deciding spec's
ID — the same convention as the architecture spec's §16.*
