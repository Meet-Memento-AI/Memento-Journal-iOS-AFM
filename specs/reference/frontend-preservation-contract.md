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
| PRES-002 | ~~Slide-out drawer, 280pt: interactive left-edge swipe (40pt zone), tap-outside-to-close, spring animation, content slides right with corner radius + shadow~~ **(SANCTIONED REMOVAL, 2026-08-16, spec 027 R4):** the drawer's edge swipe was attached to the whole `NavigationStack`, so every horizontal drag in the app arbitrated against it — irreconcilable with root paging, which now owns the horizontal axis. Removed rather than hidden, because hiding leaves the gesture installed. Its destinations are preserved under PRES-003. Second sanctioned removal after account creation (spec 023). | removed; replaced by `Components/Settings/ProfileSheet.swift` |
| PRES-003 | Drawer contents: "About yourself" and "Your journal goals/themes" + Settings — **(amended 2026-08-16, spec 027 R4)** now rows in the profile sheet, opened from the Journal header's avatar. Behavior intact; these remain the only entry point to `EditAboutYourselfView` / `EditJournalGoalsView`. | `Components/Settings/ProfileSheet.swift`; routes in `ContentView.swift` (`DrawerRoute`) |
| PRES-004 | ~~Two-tab swipeable pill nav (Journal \| Insights/Chat) with `matchedGeometryEffect` sliding glass pill and swipe-progress haptics~~ **(amended 2026-08-16, spec 027 R1/R2):** swipeable two-page root navigation and its commit haptic are **preserved** via whole-page paging; the **pill affordance is removed** — it was a third navigation surface duplicating the swipe. A mirrored corner icon on each page is the one-tap equivalent. ATTACH-03's three-tab amendment predates this shell and needs re-evaluation. | `Components/Navigation/RootPager.swift` (`RootPage`) |
| PRES-005 | ~~Floating top header shared across pages~~ **(amended 2026-08-16, spec 027 R3):** each root page owns its own header — avatar (left) and page-specific actions (right); no center pill slot. **(further amended 2026-08-17, header on the physical frame):** Journal/Chat share `RootPageScaffold`. `RootPager` expands to the physical frame so headers pin to the top of the window; glass buttons sit on `windowTop` (below the Dynamic Island) with no material behind them; footer is `windowBottom + 16`. **Narration is a mode of `AIChatView`** (same header and thread; footer/glow swap), not a sibling overlay. Do not combine that with `safeAreaInset` or `.safeAreaPadding` on chrome. Header icons 48pt; footer circles 64pt. Sheets/settings keep ambient safe areas. | `Components/Navigation/{AppHeader,RootPager,RootPageScaffold}.swift`, `ContentView.swift`, `Views/Journal/{JournalView,YourEntriesView}.swift`, `Views/AI-Chat/AIChatView.swift`, `Components/AIChat/{ChatMessagesView,NarrationFooter,NarrationGlow}.swift` |
| PRES-006 | Avatar initial renders first letter of locally stored display name, `person.fill` fallback | `AvatarInitialButton.swift`; name from local cache (spec 023 R2) |
| PRES-007 | Floating new-entry FAB on Journal tab, trailing footer slot (`windowBottom + 16`). Labeled glass capsule at that slot, black-tinted (`BaseColors.black` at 0.9) with white icon and label: **"Write your first entry"** when empty (Figma 791:2889), **"New entry"** when the list has entries. | `Components/Buttons/NewEntryFAB.swift`, `Views/Journal/JournalView.swift` |
| PRES-008 | Full-screen journal search overlay: `SearchTextField` + cancel, empty-prompt state, no-results state, result cards | `Views/Journal/JournalSearchView.swift`, `Cards/SearchResultCard.swift` |
| PRES-009 | "Entry saved" toast on save | `Components/Toast/JournalToast.swift` |
| PRES-010 | Offline banner: dismissible, non-blocking, appears when connectivity drops; journal reads/writes keep working locally | `Components/OfflineBanner.swift`, `NetworkMonitor` (2.0: offline is the *native* state per `REQ-PLAT-003`; the banner's scope shrinks to Z1-only features) |
| PRES-011 | Route enums drive all navigation (`EntryRoute` create/createWithTitle/createWithContent/`edit(UUID)`, `SettingsRoute`, `DrawerRoute`) — preserved as the deep-link surface for widgets/App Intents (ATTACH-09). Selection IDs (`selectedEntryId`, `currentSessionId`, `AppNavigationState`) are the regular-width bind points (spec 040); compact chrome stays `RootPager` + `ChatHeaderActionCluster`. | `Models/Routes.swift`, `Models/AppNavigationState.swift` |

### 2.2 Journal

| ID | Behavior | Implementation |
|---|---|---|
| PRES-020 | Entry list with four states: loading spinner, error + Try Again, empty (centered 144pt inset Memento mark; create action is the footer pill **"Write your first entry"** per PRES-007), content grouped in month-header sections | `Views/Journal/YourEntriesView.swift`, `JournalEmptyMark.swift` |
| PRES-021 | Entry cards: title/excerpt/date, pending-sync badge, tap-to-edit, delete via confirmation dialog ("This action cannot be undone") | `Cards/JournalCard.swift` |
| PRES-022 | Month-picker sheet (wheel month+year) synced to scroll position | `Views/Journal/JournalView.swift` |
| PRES-023 | Notion-style full-page editor: zooming navigation page (not a sheet — no drag handle), back, date pill, title field ("Journal title" placeholder), spacious body editor, submit arrow disabled when body empty, keyboard-aware padding. Opens/closes with the native SwiftUI zoom transition from the new-entry FAB or journal card. **(amended 2026-08-25, zoom backdrop):** the morph runs over the live root page — the journal timeline at its current scroll position, or Chat when opened from the summarize control — and never over a blank or system-colored plate. ContentView's overlay stack is layered above `RootPager` for exactly this reason, so its navigation container must stay transparent (`containerBackground(.clear, for: .navigation)` *inside* the stack plus `transparentNavigationContainer()`), and every route pushed on it must paint its own opaque fill. | `Views/Journal/AddEntryView.swift`, `EntryEditorDestination.swift`, `ContentView.swift`, `Utilities/TransparentNavigationContainer.swift` |
| PRES-024 | Editor voice-dictation FAB: expands to live duration display, red stop state, mic-permission and recording-failed alerts | `AddEntryView.swift` + speech service (2.0: `SpeechAnalyzer`, spec 018) |
| PRES-025 | Local-first entry writes; passive CloudKit sync-status line (device-neutral). Compact-width only for pager chrome. | `EntryViewModel`, `MementoDataStore` (SwiftData + CloudKit private DB; spec 015 schema, spec 040 live writes) |
| PRES-026 | Local entry search (title + content filter) | `EntryViewModel.searchEntries` (2.0: may route through Spotlight, spec 016 — behavior preserved either way) |

### 2.3 Chat / Ask (end-state class — restored by spec 019)

| ID | Behavior | Implementation |
|---|---|---|
| PRES-040 | Empty state: Memento glyph, headline **"Let’s dive deeper into your journal"** (no name greeting), **(amended 2026-08-27)** full-viewport **vertical** scroller of logo + headline + **full-width stacked** suggestion tiles (theme pill + arrow, then prompt). The third tile peeks behind the composer. Starters rotated from local `AISuggestionPrompts.json` plus confirmed ThemeCatalog pills. | `Views/AI-Chat/AIChatView.swift`, `ChatMessagesView.swift`, `AISuggestionCard` |
| PRES-041 | Three-state input field: default (history pill + "Chat with Memento" pill + voice pill) / text-active (1–5 line expanding field + send) / voice-active (inline listening panel: cancel/confirm, audio-reactive dots, transcription auto-send) | `Components/AIChat/ChatInputField.swift`, `AIChatFooter.swift` |
| PRES-042 | Message rendering: user bubbles right-aligned; AI responses full-width with typewriter reveal (~120 cps), heading/body structure, markdown-safe parsing, JSON never shown raw | `ChatMessageBubble.swift`, `AIOutputComponent.swift`, `RichTextParser.swift` |
| PRES-043 | Response action bar: copy, thumbs up (persisted positive), thumbs down (persisted negative + reason sheet), regenerate, overflow → Report answer | `AIOutputComponent.swift` (spec 041: `AnswerFeedbackStore`; 2.0 eval feed remains spec 022) |
| PRES-044 | Citations: "N journals" tag on grounded responses → bottom sheet with citation timeline (date tags, tappable items) | `CitationLink.swift`, `CitationsBottomSheet.swift`, `CitationTimelineList` (2.0 upgrade: tap-through to the cited entry, spec 019) |
| PRES-045 | Chat history: sheet with drag handle, New-chat button, loading/empty states, sessions titled by first message with relative dates, tap-to-load, swipe-to-delete | `ChatHistorySheet.swift`, `ChatHistoryList.swift`, `ChatHistoryItem.swift` (2.0: `Conversation`/`Turn` entities, spec 015) |
| PRES-046 | Summarize-chat-to-entry: sheet offer → generated summary prefills the entry editor. **(restored 2026-08-16)** The feature had silently become unreachable: `showSummarySheet` was never set to `true` anywhere in the app after per-page headers replaced the shared one, and the flow existed in two divergent copies — ContentView's (correct, orphaned) and AIChatView's (reachable in principle, but its `AddEntryView.onSave` never called `createEntry`, so summaries were dropped). Now a single path: chat's header `sparkles` control → `ChatSummarySheet` → `onPresentEntry(.createWithContent(...))` → ContentView overlay `NavigationStack` (`EntryEditorDestination`), the only site that persists. **Known gap:** `ChatService.summarizeChat` returns `ChatSummaryResponse(title: nil, …)`, so the title is always the `"Chat Reflection"` fallback — the view layer no longer hardcodes it, but nothing generates one yet. | `ChatSummarySheet.swift` → `AddEntryView` (2.0: Z0 summarization via `IntelligenceService`); trigger in `Views/AI-Chat/AIChatView.swift`, persistence in `ContentView.swift` |
| PRES-047 | Failure handling: per-message "Failed to send · Retry" row, error alert with Retry, typing indicator during generation | `ChatMessageBubble.swift`, `AILoadingState.swift` |
| PRES-048 | Honest gating states: offline empty state ("needs a connection" — 2.0: only for Z1 with Z0 degradation per `REQ-INT-009`) and AI-disabled state with Enable action (`PreferencesService.aiEnabled`) | `AIChatView.swift` |

### 2.4 Onboarding (account step removed by spec 023)

| ID | Behavior | Implementation |
|---|---|---|
| PRES-060 | Welcome: looping video background with progressive blur + staged dissolve, logo, headline — auth buttons replaced by single "Get Started" (spec 023 R2) | `Views/Onboarding/WelcomeView.swift`, `Components/VideoBackground.swift` |
| PRES-061 | Step order: YourName → LearnAboutYourself → ThemeConfirmation → app-lock setup → LoadingStateView; back from first step returns to Welcome | `OnboardingCoordinatorView.swift` |
| PRES-062 | Name collection (first + last, continue gated on both) populates the local display name | `YourNameView.swift` |
| PRES-063 | "Learn about yourself" free-text step with voice-dictation FAB and live duration; the text is stored as **About yourself** preferences (`LocalProfileStore` / Experience Profile reflection) and seeds theme estimation — it is **not** written as a journal entry | `LearnAboutYourselfView.swift`, `OnboardingViewModel.savePersonalizationText` |
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
| PRES-082 | AI Features toggle with reactive subtitle — 2.0: the generative **off** switch. Turns generation off entirely; it is *not* the Z0 pin (see PRES-087) | `SettingsView.swift`, `PreferencesService.aiEnabled` |
| PRES-087 | "On-Device Only" toggle with reactive subtitle — `REQ-INT-004`'s Z0 pin, shown only when AI Features is on. Read by `ModelRouter` at the intelligence boundary, never per-surface, so no surface can escape it | `SettingsView.swift`, `PreferencesService.processOnDeviceOnly` |
| PRES-083 | Data-usage transparency sheet — content rewritten for 2.0 (no Gemini/Supabase; zone language per spec 014) but the *surface* persists | `DataUsageInfoView.swift` |
| PRES-084 | Profile name edit (≤50 chars, save feedback) against the local cache | `ProfileSettingsView.swift` |
| PRES-085 | Sections merged into one "Your Data" section: profile, AI toggle, privacy policy, data-usage sheet, export (new, spec 015), Delete Everything (spec 023 R4). Sign Out removed | `SettingsView.swift` |
| PRES-086 | Drawer editors: "About yourself" (personalization text, voice FAB, 100-char minimum counter) and "Your journal goals" (re-select chips) — both against local storage | `EditAboutYourselfView.swift`, `EditJournalGoalsView.swift` |

### 2.7 Design system

| ID | Behavior | Implementation |
|---|---|---|
| PRES-090 | Token system: gray/primary scales, full semantic palette with documented WCAG AA/AAA ratios, emotion colors (dark-mode brightened), gradients, radius scale, glass tokens. **(amended 2026-08-17 — B&W canvas.)** Light `theme.background` / `theme.card` / `theme.popover` / `theme.inputBackground` are `#FFFFFF`. `GrayScale` 50–400 are cool greys (`#FFFFFF`→`#A3A3A3`); `gray800`/`gray900` stay warm ink; `gray950` is true black `#000000` for dark canvas (raised dark cards `#111111`). **`theme.primary` is ink** (`PrimaryScale.primary900` `#2C1E19` light, `#FFFFFF` dark) for filled buttons and block CTAs. **`theme.accent` is mid-brown** (`BrandColors.brand` `#A87549` / `brandDark` `#C89A6E`) for highlights only (sparkles, citations, speaking, focus). `brandOnText` `#895C37` wherever brown *is* text (`#A87549` is 3.96:1 on white, below AA). `AccentColor` follows ink, not mid-brown (spec 002 R3). Liquid Glass stays untinted (PRES-092). All ratios in `Theme.swift` were **re-measured** against the new hexes. | `Resources/Theme.swift` (CONSTITUTION §3 canonical), `Assets.xcassets/AccentColor.colorset` |
| PRES-091 | Typography: Figtree (UI: h3–h6, body, caption) + Lora serif (h1/h2 display and onboarding), h1–h6/body/caption scale, Dynamic Type via `relativeTo:`/`ScaledMetric` with accessibility cap | `Resources/Typography.swift` (CONSTITUTION §3 canonical) |
| PRES-092 | Liquid Glass surfaces render as one system. **(re-adopted 2026-08-16, superseding the 2026-08-07 removal.)** The removal was made against Simulator rendering — where glass is expected to read flat gray — and spec 024's device pass (its Task 7) was never completed. Two concrete causes were found and fixed: an **opaque `ScrollEdgeFade(.top)` scrim** painted directly behind the floating header, leaving glass nothing to refract; and **adjacent glass with no shared sampling region** (glass cannot sample glass), which read as stacked/double glass. Rules now in force: one `GlassEffectContainer` per adjacent cluster, spaced to match the layout; `.glassEffect` applied to the view **containing** the content, never as a sibling `.background(...)`, or the content gets no vibrancy treatment; never an opaque fill or scrim beneath glass; `.regular` only, untinted; content-layer surfaces (list rows, cards, the crisis card) stay flat. `theme.glassBorder` remains a non-glass insight-card stroke and is **not** a glass API. **(2026-08-16)** `ScrollEdgeFade` — the opaque scrim named above — is now deleted outright rather than merely unused at the top edge; see PRES-095. | `Components/Navigation/AppHeader.swift`, `Components/Buttons/{AvatarInitialButton,NewEntryFAB}.swift`, `Components/AIChat/ChatInputField.swift`; scroll edges in `YourEntriesView.swift` / `AIChatView.swift`; tokens in `Resources/Theme.swift` |
| PRES-093 | Haptic vocabulary: impact on taps/tabs/record, notification haptics on success/error — pervasive, part of the product feel (`REQ-SYS-014` extends this) | throughout Views/Components |
| PRES-094 | Motion: spring animations, matched-geometry pill/FAB transitions, typewriter reveals, progressive blur + scroll-edge fades — all respecting Reduce Motion. **(amended 2026-08-16)** Both named components are **deleted**. `ScrollEdgeFade` painted an opaque `theme.background` gradient — it hid content instead of softening it, and an opaque scrim under glass is what PRES-092 forbids. `ProgressiveBlurHeaderWrapper` never had a call site. Both are replaced by `ProgressiveBlurEdge`, a masked-material band used at the top (inside `AppHeader`, so all three header sites share it) and the bottom of both root scroll views. | `Components/ProgressiveBlurEdge.swift`, `Components/Navigation/AppHeader.swift`, component-level |
| PRES-095 | Scroll edges are **translucent, never opaque, and never clipped**. Content passes under the chrome and blurs into it. Three rules, each learned from a regression: (1) the system `scrollEdgeEffectStyle` draws only where a system bar exists — this app hides the nav bar, so it rendered a hard white slab that sliced entry titles; both root scroll views set `scrollEdgeEffectHidden(true, for:)` instead. (2) Never put an opaque fill behind `AppHeader` — glass samples the scrolling content. (3) `ProgressiveBlurEdge` in `AppHeader` covers only the island / status-bar strip (`windowTop`), not the glass row; it must fade to clear **above** the buttons. | `Components/ProgressiveBlurEdge.swift`, `Components/Navigation/AppHeader.swift`, `Views/Journal/YourEntriesView.swift`, `Views/AI-Chat/AIChatView.swift` |
| PRES-096 | **No private API.** `ProgressiveBlurHeader` / `VariableBlur` were removed from the project entirely (2026-08-16): they resolved `CAFilter` and `filterWithType:` through reversed-string lookup (`String("retliFAC".reversed())`) and swapped `CABackdropLayer.filters` — deliberate evasion of static analysis, and a Guideline 2.5.1 rejection risk. They were linked but unused. Any future progressive-blur work must stay on public API; verify with `strings <binary> \| grep retliFAC` returning nothing. | `MeetMemento.xcodeproj/project.pbxproj`, `Package.resolved` |
| PRES-095 | Loading affordances: shimmer skeletons, modern progress ring, rotating tip cards | `Components/Data/SkeletonView.swift`, `Components/Loading/*` |

---

## 3. ATTACH map — where 2.0 surfaces mount on the preserved shell

| ID | 2.0 surface | Mount point | Must respect | Owning spec |
|---|---|---|---|---|
| ATTACH-01 | Ask (chat over history) | Replaces the "Insights" tab's *backing service*; the surface itself is the restored §2.3 chat UI | PRES-040…048 in full | 019 |
| ATTACH-02 | Weekly reflection | Card at top of the Journal timeline + the single "weekly reflection ready" notification; listenable per spec 018 | PRES-020, PRES-009 | 019 |
| ATTACH-03 | Patterns / Monthly | **Third pill tab** (Journal \| Chat \| Patterns) — the one sanctioned amendment to PRES-004, decided 2026-07-23; evaluate §4 reuse-ledger chart components first | PRES-004 (amended), PRES-005 | 019 |
| ATTACH-04 | Entry reflection (Z0, at save) | Entry detail/editor surface — title/summary/mood/topics appear on the saved entry; observation only when salience warrants | PRES-021, PRES-023 | 019 |
| ATTACH-05 | TTS narrate / Personal Voice | ~~Reflection surfaces (weekly/monthly/entry) — never chat~~ **(amended 2026-08-16, spec 018 R7 + CONSTITUTION):** extended to **post-stream chat message playback**; playback never runs mid-stream. `NarrateButton`/`ListeningPanel` were **consumed** — deleted and replaced by `Services/VoicePlaybackService.swift` + `Utilities/SpeechTextSanitizer.swift`, with `Components/AIChat/DictationWaveform.swift` superseding `ListeningDotsView`. | PRES-093, PRES-094 | 018 |
| ATTACH-06 | Export (Markdown/JSON) | "Your Data" settings row | PRES-085 | 015 |
| ATTACH-07 | Paywall (new — no monetization UI exists today) | Gates reflections/patterns/ask/Personal Voice per `REQ-MON-003`; never gates capture/timeline/search/export | PRES-085, free-tier surfaces untouched | 021 |
| ATTACH-08 | Notification preferences (new) | Settings — exactly two notifications exist (opt-in daily reminder, weekly-ready) | PRES-085 | 019/020 |
| ATTACH-09 | Widgets / Controls / App Intents / Live Activity | Deep-link through the existing route enums (`EntryRoute.create`, `EntryRoute.edit(UUID)`, etc.); recording Live Activity pairs with the dictation FAB durability contract | PRES-011, PRES-024 | 020 |
| ATTACH-12 | Multi-device selection IDs (no iPad chrome in 040) | `selectedEntryId` / `currentSessionId` / `AppNavigationState.primarySection` so a later regular-width shell can bind without rewriting compact pager | PRES-011, PRES-025 | 040 |
| ATTACH-10 | Journaling Suggestions picker | Composer (editor) as a seeded prompt + attachment | PRES-023 | 018 |
| ATTACH-11 | Trust-zone indicator (P4: boundary as UI element) | Generated-content surfaces (reflection cards, chat responses) — new, from spec 014's reusable component | PRES-042, PRES-090 | 014/019 |

## 4. Reuse ledger — deprecated/orphaned code worth claiming

Not contract. Each row is either claimed by a 2.0 spec or deleted during that
spec's rebuild — no third option (unclaimed zombie code violates spec 001's
hygiene standard).

| Component(s) | State today | Claim candidate | For |
|---|---|---|---|
| `InsightsView` + `InsightsContentView` (typewriter headline, staggered reveal, month cache), `SentimentAnalysisCard`, `PercentageBarChart` (WCAG-AAA emotion tokens), `KeywordsCard`, `FollowUpQuestionGroup`, `InsightMonthPickerSheet`, `EntriesTag`, `InsightsThemeTag`, `InsightsThemesSection` | Deprecated — chart-based Insights, off main nav. `InsightsView` + `InsightsContentView` **deleted 2026-08-27** (commit `4e73546`, unreachable). `PercentageBarChart` **de-crashed 2026-08-27** — five release-trapping `precondition`s replaced with clamping (MEM-47); kept, not deleted, because 019 R4's claim below is still open | **Spec 019 Patterns** — this is a substantially built starting point for the Patterns tab (ATTACH-03); `FollowUpQuestionGroup`'s tap-to-create-entry flow is directly reusable | Patterns/Monthly |
| `NarrateButton`, `ListeningPanel`, `ListeningDotsView` | ~~Orphaned (ChatInputField grew its own inline panel)~~ **CONSUMED 2026-08-16 (spec 018 R7)** — deleted; role absorbed by `Services/VoicePlaybackService.swift`, `Utilities/SpeechTextSanitizer.swift`, and `Components/AIChat/DictationWaveform.swift` | ~~Spec 018 TTS starting points~~ claimed and closed | Voice output |
| `JournalReviewIndicator` ("Reviewed N journals") | ~~Orphaned~~ **DELETED 2026-08-27** — unused; Ask retrieval-transparency will be built new when that affordance ships | closed | Ask |
| `MonthlyInsightCard`, `AISummarySection`, `SummaryCard`, `InsightCard` | ~~Orphaned~~ **DELETED 2026-08-27** — Weekly/Monthly card design references not reused | closed | Weekly card |
| `InlineCitationBadge`, `CitationPopover`, `CitationFlowText` | ~~Orphaned (sheet-based citations won)~~ **DELETED 2026-08-27** — sheet path (`CitationsBottomSheet`) remains the Ask citation UI | closed | Ask citations |
| `WordCounterNavButton`, `ChatEmptyState`, `InsightAnnotationsSection`, `InsightDateTag`, theme-tag family (`ThemeSection`/`ThemeTag`/`OnboardingThemeTag`), `Chip`, `IconButton`, `BaseTagStyle`, `BottomTab`/`BottomTabsNav`, `TopNav` `.single` variants | ~~Orphaned~~ **DELETED 2026-08-27**. `InsightsThemesSection` / `InsightsThemeTag` stay with the Patterns chart row above. Live theme picking is `SelectableThemeTag`; live FAB is `NewEntryFAB`; live header icons are `HeaderIconButton` / `IconButtonNav`. | closed | — |
| `OTPTextField` | Live only in the deleted email-OTP path | Delete with spec 023 R1 (PIN boxes are bespoke, not this component) | — |
| `Configuration.storekit`, `SubscriptionPlan.swift` | Present, unwired | Spec 021 builds monetization new; evaluate then | Paywall |

---

*End of contract. Amendments require a dated note here plus the deciding spec's
ID — the same convention as the architecture spec's §16.*
