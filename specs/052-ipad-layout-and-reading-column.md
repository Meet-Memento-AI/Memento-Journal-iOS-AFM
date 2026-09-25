---
id: 052
title: iPad Layout and Reading Column
tier: P1
status: in-progress (2026-09-24)
effort: 1 session
depends_on: [027, 040]
findings:
  - ipad-runs-a-phone-layout-at-ipad-size
  - reading-column-metric-applied-to-nothing
  - root-chrome-aligns-to-the-window-not-the-content
source_refs: [REQ-PLAT-001]
pres_refs: [PRES-005, PRES-020, PRES-023, PRES-040, PRES-041, PRES-092, PRES-095]
---

# 052 — iPad Layout and Reading Column

**Traceability:** the follow-on UI spec [040](040-ipad-backend-readiness.md) named
in its *Does not implement* list. 040 delivered the data layer, device-neutral
copy, and the regular-width selection IDs; this spec delivers the **measure and
spacing** half. Compact chrome remains [027](027-navigation-redesign.md) —
`RootPager` and the per-page `AppHeader` are preserved, not replaced.

**Does not implement:** iPad `NavigationSplitView`, a sidebar shell, hardware
keyboard chrome, or a multi-column journal grid. Those remain a later spec, with
040 R5's selection IDs (`selectedEntryId`, `EntryRoute.edit(UUID)`,
`AppNavigationState`, `ChatViewModel.currentSessionId`) still waiting for them.

## Why

CONSTITUTION §1 says universal iPhone+iPad, and `TARGETED_DEVICE_FAMILY` is
`"1,2"` with all four orientations enabled on iPad. But every primary surface is
`frame(maxWidth: .infinity)` behind a 16pt gutter, so on a 13″ iPad in landscape
(1366pt) a journal card is ~1334pt wide, the chat composer is ~1334pt wide, and
the header's avatar and action cluster sit ~1300pt apart at opposite window
edges. `docs/app-store/00-readiness-checklist.md` D9 requires iPad 13″
screenshots, so this is visible on the store listing.

`ContentColumnMetrics` already existed (commit `e1f7545`) and was wired into
onboarding only — its own commit message says *"Not yet applied to any view."*

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Root chrome spans the window | `Components/Navigation/AppHeader.swift` `rootEdgeInset()` — `containerRelativeFrame { max(length - 32, 0) }`, unbounded | High |
| 2 | Journal timeline unconstrained | `Views/Journal/YourEntriesView.swift` `.padding(.horizontal, 16)` on the `LazyVStack` | High |
| 3 | Chat transcript, composer, narration footer unconstrained | `ChatMessagesView.swift`, `ChatInputField.swift`, `NarrationFooter.swift` — four `rootEdgeInset()` sites | High |
| 4 | FAB parks at the window edge | `Views/Journal/JournalView.swift` footer `HStack` | Medium |
| 5 | Editor body is a ~1300pt line of prose | `Views/Journal/AddEntryView.swift` | High |
| 6 | 13 prose/list sites unconstrained | `Views/Settings/*.swift` ×9, `JournalSearchView`, `Insights/WeeklyReflectionView` (×2) | Medium |

## Requirements

### R1. Two named measures, iPhone provably inert
`ContentColumnMetrics.reading = 600` (prose) and `surface = 720` (timelines,
transcripts, and the chrome aligned to them). `maxWidth` is retained as an alias
for `reading`.

`surface` is 720 rather than ~768 because iPad mini is 744pt in portrait: at 768
the mini would never clamp and 11″ portrait (834pt) would clamp by 33pt — a
margin too small to read as deliberate. 720 gives every iPad a visible margin.

**Acceptance:** no idiom or size-class branch is introduced. Every clamp resolves
to the untouched proposal at all eight iPhone portrait widths (320…440), and
capped chrome resolves to exactly `width - 2 × edgeInset` — byte-identical to
`rootEdgeInset()`. Asserted as arithmetic in `ContentColumnTests`.

### R2. The page declares its column; shared chrome reads it
An environment key `\.contentColumnWidth` (default `reading`) is set to `surface`
once, on `RootPager` in `ContentView`. `AppHeader` and the editor's own header
read it via `pageColumnRelative()`.

**Acceptance:** `ContentColumnMetrics.surface` appears at exactly one call site in
the app target. `AppHeader` hardcodes no measure, so a header mounted above prose
cannot sit outside the text column. The overlay `NavigationStack` is a sibling of
the pager, so Settings and the entry editor inherit `reading` without opting in.

### R3. Width authority for chat stays on the ScrollView
`ChatMessagesView` reports the inset ScrollView's frame into
`choreographer.columnFrame`, which is the only width the send flight has:
`ChatTranscriptMetrics.landingRect` places the ghost at `column.maxX` and
`SendFlightGhost` wraps at `UserBubbleSurface.maxWidth(inColumnWidth:)`. The cap
replaces `rootEdgeInset()` **in place**; the inset is not moved onto the scroll
content.

**Acceptance:** a capped column lands the ghost on the column's trailing edge; a
full-window column misplaces it by half the leftover margin (323pt on a 13″
iPad). Both asserted against the real function.

### R4. Prose keeps its fill full-width and its content leading-aligned
`proseColumn()` is three frames — greedy-and-leading, cap, centre — applied
*inside* the `ScrollView` so `.background(theme.background.ignoresSafeArea())`
still spans the window.

**Acceptance:** no prose route lets the root pager show through beside it
(PRES-023 requires each overlay route to paint its own opaque fill). Short copy
stays leading-aligned on iPhone rather than becoming centred.

### R5. The editor is prose end to end
`AddEntryView`'s body, header row and footer all take `reading`. The cover photo
stays full-bleed: the backdrop layers are `.ignoresSafeArea()` siblings that read
no content width.

**Acceptance:** the back chevron sits on the text column's edge, not 60pt outside
it. `shaderRevealProgress` and `JournalBackdropRenderer` are untouched — PRES-023's
2026-09-10 device-freeze note still holds (no live filter, animated transform, or
per-frame glass rebuild on that layer).

### R6. Liquid Glass rules preserved
The cap is applied to the header's `HStack` inside the existing single
`GlassEffectContainer`. The `ProgressiveBlurEdge` island strip and the outer
`.frame(maxWidth: .infinity)` stay full-bleed.

**Acceptance:** one glass cluster per header, no opaque fill beneath glass, no
second container (PRES-092). Verified on device — the Simulator renders glass flat.

## Out of Scope

- iPad split-view / sidebar shell, hardware keyboard chrome — later spec.
- **Size-class gutter (24pt on regular).** Deliberately deferred: the gutter is
  hardcoded at ~14 sites, and moving chrome to 24 without converting all of them
  gives chrome at 24 over content at 16 — an 8pt misalignment worse than today's
  uniform 16. Its own PR, converting every site in one commit. Note for it: iPad
  in Slide Over reports `.compact`, so read the size class live, never cache it.
- Multi-column journal grid — changes `YourEntriesView`'s month grouping and the
  `matchedTransitionSource` contract PRES-023 depends on.
- Sheet sizing. iPad form sheets are ~540pt, already below `reading`, so a cap
  would be inert. The eight `presentationDetents` sites are verify-only.

## Tasks

- [x] 1. `reading` / `surface` / `maxWidth` alias, `contentColumnCentered`,
      `proseColumn`, and the `\.contentColumnWidth` environment (R1, R2).
- [x] 2. Arithmetic tests, authored before the view edits (R1, R3).
- [x] 3. 11 prose sites via `proseColumn()`; search via `pageColumn()` (R4).
- [x] 4. Journal timeline and FAB (R1).
- [x] 5. `AppHeader` + the one `contentColumnWidth` declaration (R2, R6).
- [x] 6. Four chat sites, one commit (R3).
- [x] 7. Entry editor, three bands at `reading` (R5).
- [ ] 8. Verification below. **Blocked on this machine** — see Verification.

## Verification

- [ ] `xcodebuild -scheme withMemento -destination "$IOS_SIM_DESTINATION" -skip-testing:withMementoUITests -parallel-testing-enabled NO test` green; coverage floor 13 holds (ratchet-only).
- [ ] iPhone 17: Journal, Chat, editor, Settings pixel-identical to `main`.
- [ ] iPad Pro 13″ portrait **and** landscape: chrome on the column edges; timeline and transcript at 720; editor prose at 600 over a full-bleed cover; FAB under the column.
- [ ] iPad mini (744pt portrait): the narrowest iPad still shows a margin.
- [ ] Split View / Stage Manager at ~507pt: degrades to gutter-only, no column wider than the window.
- [ ] Send choreography on iPad landscape: long message near a wrap boundary, no reflow at the ghost handoff. Also `reduceMotion` on (no ghost path), VoiceOver on, keyboard up/down, rotate mid-flight.
- [ ] Editor zoom transition from the FAB and from a card; "View memory" reveal at both ends.
- [ ] Liquid Glass on a physical device: one header cluster, no double glass.

**Environment blocker (2026-09-24):** this Mac has **Xcode 26.6** and the project
targets iOS 27, so `withMemento` does not compile here — `FoundationModelsIntelligenceService.swift`
fails on `LanguageModelError`, `GeneratedContent.ParsingError`,
`SystemLanguageModel.Error`, and `Attachment`. **Verified identical on a clean
tree with the 052 changes stashed**, so it is pre-existing and unrelated (see
commit `9fbad5a`, "Record that the build Mac cannot currently build the app").
Every changed file parses cleanly (`swiftc -parse`), but nothing above has been
compiled, tested, or seen. Run this list on an Xcode 27 machine before closing.

## Regression Guards

CONSTITUTION §1 universal app; §4 rules 4 (Typography tokens — untouched) and 6
(new work ships with tests). PRES-005 (per-page headers, now column-aligned),
PRES-020/021 (entry list and cards), PRES-023 (editor, backdrop, zoom
transition), PRES-040/041 (chat empty state and composer), PRES-092 (one glass
cluster, no opaque fill beneath glass), PRES-095 (translucent scroll edges).
Spec 027's compact shell and spec 040 R5's selection contracts are unchanged.
