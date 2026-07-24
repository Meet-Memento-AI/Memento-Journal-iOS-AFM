---
id: 020
title: System Integration and Accessibility
tier: P2
status: in-progress (2026-07-24) — Requirements derived; DEC-005 open, REQ-SYS-002 gated on DEC-002, per-intent privacy manifest verification outstanding
effort: 3 sessions
depends_on: [019]
findings: [entry-points-not-new-surfaces, indexed-entity-shares-dec-002-gate, widget-redaction-lock-contract, watch-decision-framed-not-made, a11y-conventions-already-in-tree]
source_refs: [REQ-SYS-001, REQ-SYS-002, REQ-SYS-003, REQ-SYS-004, REQ-SYS-005, REQ-SYS-006, REQ-SYS-007, REQ-SYS-008, REQ-SYS-009, REQ-SYS-010, REQ-SYS-011, REQ-SYS-012, REQ-SYS-013, REQ-SYS-014, REQ-A11Y-001, REQ-A11Y-002, REQ-A11Y-003, DEC-005]
tech_refs: [technology/07-app-intents-and-surfaces.md, technology/09-ui-swift6-testing.md]
---

# 020 — System Integration and Accessibility

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§10 "System integration" in full.

## Why

Where the Apple-ecosystem strategy converts into defensibility a minimalist
competitor (Slate) structurally will not build: App Intents/Siri, widgets/
Controls/Live Activities, Watch, Focus/Shortcuts, and accessibility — each cheap
individually, a moat together. Depends on spec 019 because most of these surface
existing capabilities (capture, weekly reflection, ask) through new entry points
rather than building new capability.

**Absorbs spec [008](008-dynamic-type-and-accessibility.md)** (obsolete,
pre-2.0): this spec's `REQ-A11Y-001`–`003` work should re-run 008's
`.system(size:)`/VoiceOver inventory against the post-2.0 Views built in spec
019, not reuse 008's now-stale pre-2.0 evidence table.

## Technology References

- `specs/reference/technology/07-app-intents-and-surfaces.md` — primary:
  `AppEntity`/`IndexedEntity`/`EntityQuery`, `AppShortcutsProvider`, SiriKit
  deprecation, WidgetKit, `ControlWidget`, ActivityKit Live Activities,
  `BGTaskScheduler`.
- `specs/reference/technology/09-ui-swift6-testing.md` — accessibility
  (VoiceOver/Dynamic Type/Reduce Motion/Reduce Transparency/Voice Control),
  Liquid Glass tokens, Core Haptics, Swift 6 actor-isolation table.

## Current State (evidence)

No `CoreSpotlight`, `AppIntent`, `INIntent`, or `NSUserActivity` usage found
anywhere in `MeetMemento/`; no Spotlight-related keys in `Info.plist` or
`MeetMemento.entitlements` (confirmed 2026-07-23) — fully greenfield.
Accessibility labels currently exist on 39/151 files via
`MeetMemento/Utilities/AccessibilityHelpers.swift` (per `CONSTITUTION.md` §2) —
this baseline was spec 008's pre-2.0 evidence table. Spec 008 is now obsolete
(2026-07-23), fully absorbed into this spec (see "Absorbs spec 008" above): this
spec's `REQ-A11Y-*` work supersedes 008's — re-run its `.system(size:)`/
VoiceOver inventory against the post-2.0 Views built in spec 019, plus the
2.0-specific additions TTS-driven audio-usability and Voice Control labels on
new surfaces bring — rather than treating 008 as separately still-open work.

## Requirements

**Traceability:** R1 → `REQ-SYS-001`, `REQ-SYS-004`; R2 → `REQ-SYS-002` (gated
— gate owned by spec 016 R1); R3 → `REQ-SYS-003` (§16 item 13 / V20,
verify-first); R4 → `REQ-SYS-005`–`008` + `technology/07` §2's widget-privacy
rule; R5 → `DEC-005`, `REQ-SYS-009`, `REQ-SYS-010` (decision framed, **not**
made); R6 → `REQ-SYS-011`; R7 → `REQ-SYS-012`, `REQ-SYS-013`, `REQ-SYS-014`;
R8 → `REQ-A11Y-001`–`003` (absorbing obsolete spec 008's scope per the 013 R6
disposition in `ROADMAP.md`); R9 → source doc §16 ownership.

**Zone tags (spec 014 R1) — this spec adds entry points, never new zones.**
Nothing in this spec performs generation or decides routing: every intent,
widget, control, and Live Activity here is an *entry point into* or a
*rendering of* capability owned elsewhere. Capture paths are `.z0Device`
(spec 018); "Ask my journal" runs spec 017 R2's Ask row (Z1 `.light` → Z0)
with spec 014 R2's disclosure semantics; widgets and "Read my weekly
reflection" render **already-persisted** artifacts — Z0 rendering of content
whose zone was recorded at generation time (spec 014 R1's persisted-zone
contract). Any surface in this spec that would introduce its own network call
or zone decision is out of contract by construction.

### R1. Four App Intents + `AppShortcutsProvider`; zero SiriKit (`REQ-SYS-001`, `REQ-SYS-004`)
Exactly the four intents of §10.1, registered via `AppShortcutsProvider` with
natural phrases — and no more: `technology/07` §1's guidance (three-to-five
actions, or Siri disambiguation degrades) makes four the whole list, not a
starting point.

| Intent | Parameters | Backing capability (cited, not rebuilt) |
|---|---|---|
| **New entry** | optional spoken content | Spec 018 R1/R3 capture pipeline, Z0. With spoken content: saves without opening the app. Without: deep-links `EntryRoute.create` (PRES-011, ATTACH-09). |
| **Read my weekly reflection** | — | Returns audio via spec 018 R7's `ReflectionAudioRenderer` over the persisted artifact. Never triggers generation; if no artifact exists, it says so (a designed reply, not an error). |
| **Ask my journal** | question | Spec 017's `IntelligenceService` Ask path; returns a snippet. Degradation/quota state disclosed in the snippet per spec 014 R2's semantics — never a silent, unlabeled Z0 answer. |
| **Find entries about** | topic/date | Entity results — requires R2's `EntityQuery`, so this intent's result type is sequenced **after** R2's gate clears. |

- **Entry points, not new surfaces:** intents deep-link through the existing
  route enums (PRES-011) into the surfaces spec 019 built. Spec 019 R1
  explicitly hands widget/Control-Center/intent entry-point ownership here
  (ATTACH-09) and keeps the < 400ms composer budget *on the route*: this
  spec's obligation is that every capture entry point invokes
  `EntryRoute.create` and adds no blocking work in front of it, so 019's
  measured budget holds regardless of where the tap came from.
- **Lock gating:** with app lock enabled (spec 023 R6's shipped policy,
  inherited by spec 015 R3), content-returning intents (Read weekly, Ask,
  Find) MUST require authentication before returning journal content — no
  transcript, reflection text, or entity title in a Siri response on a locked
  device. This is the intent-scale instance of the same contract 015 R3
  states for Spotlight visibility.
- **`REQ-SYS-004`:** SiriKit is deprecated in iOS 27 (✅ `technology/07` §1).
  No SiriKit code, ever.
- **Verify-first (owned here, not §16-numbered):** V21 — is there a
  journaling domain schema? If not, use the generic entity path; do not block
  on it. V22 (View Annotations) is explicitly deferred until after core
  surfaces ship, per `technology/07` §1.

**Acceptance (Given/When/Then):**
- Given the app installed, when App Shortcuts are enumerated, then exactly
  the four intents appear with natural phrases — no fifth action.
- Given "New entry" invoked via Siri with spoken content, when the intent
  completes, then the entry is saved through spec 018's pipeline (Z0,
  airplane-mode testable) without the app opening.
- Given app lock enabled and the app locked, when any content-returning
  intent runs, then the response contains no journal content and directs to
  unlock — App Intents Testing framework test (✅ `technology/09` §7, real
  system pathways, no UI automation).
- Given the app target, when grepped for `import Intents`/`INIntent`/
  `INExtension`, then zero matches.
- Given each of the four intents, when the App Intents Testing suite runs,
  then each has at least one passing test through real system pathways.

### R2. `Entry` as `AppEntity`/`IndexedEntity` (`REQ-SYS-002`) — **gated on `DEC-002`, not implementable before it**
`IndexedEntity` donation feeds the same Spotlight semantic index the search
tool reads (`technology/07` §1) — it is `DEC-002`'s visibility question in
App Intents clothing. Per this spec's own gate note and spec 016 R1's entry
condition: **no `REQ-SYS-002` implementation begins until spec 016 R1's
one-line branch declaration exists** (which itself consumes spec 013 R1's
written verdict — "hidden" / "partially hidden" / "not hidden", with cited
API). This R-block therefore specifies both branches and waits:

- **Branch A (`DEC-002` positive):** `Entry` conforms to `AppEntity` +
  `IndexedEntity`; the attribute set is built by spec 016 R2's *same*
  `makeSearchableItem` maker (`REQ-IDX-002`: one code path serving Siri,
  Spotlight, and the search tool — cited, never a second donation path here).
- **Branch B (`DEC-002` negative):** `AppEntity`/`EntityQuery` conformance
  still ships (Siri can act on entries the app hands it), but `IndexedEntity`
  exposure follows spec 016 R4's opt-in posture — donation only for users who
  opted in (`excludedFromIndex` defaults true), and "Find entries about"
  results for non-opted-in users come via the `REQ-IDX-007` fallback tool's
  data path.
- Either branch: `EntityQuery` supports property-based and string-based
  lookup plus `suggestedEntities()`; lock gating per R1 and spec 016 R2's
  `REQ-DATA-004` evidence.

**Acceptance (Given/When/Then):**
- Given this R-block's implementation is proposed, when spec 016's file is
  read, then R1's branch declaration line exists there first — no
  `IndexedEntity` conformance lands in any commit that precedes it.
- Given fixture entries on a real device, when donated via entity conformance,
  then system-wide Spotlight behavior matches the declared branch (016 R2's
  real-device acceptance, re-run through the App Intents path).
- Given an `EntityQuery` string lookup for a fixture entry title, when
  executed under the App Intents Testing framework, then the correct entity
  returns with display representation (title + date), and its attribute set
  is byte-equal to 016 R2's maker output for the same entry.

### R3. Per-intent privacy declarations (`REQ-SYS-003`) — verify-first, §16 item 13 / V20
The mechanism itself is 🔴 UNVERIFIED (`technology/07` §1): secondary sources
report iOS 27 adds per-intent privacy manifest declarations to keep sensitive
interactions on-device. Written verify-first:

1. **Close V20 first** — confirm against the iOS 27 SDK/privacy-manifest
   documentation whether per-intent declarations exist and what they declare.
   Unblocked by installing the Xcode 27 beta (standing blocker, not installed)
   and diffing the privacy-manifest schema; record the finding in
   `technology/11-verification-queue.md` V20 either way.
2. **If the mechanism exists:** every Memento intent is declared on-device —
   a journal has no intent whose interaction should leave the device
   undisclosed; this is a blanket rule, not per-intent judgment.
3. **If it does not exist:** record that in V20 and note that the property it
   would have declared is already true by construction — R1's table routes
   every intent through Z0 paths or 017's disclosed Z1 path; no intent gets a
   zone of its own.

**Acceptance:** V20 is closed-with-findings (or documented-as-attempted)
before Tasks 2/3 are checked off; if the mechanism exists, a manifest audit
shows every shipped intent declared on-device.

### R4. Widgets, Controls, Live Activities (`REQ-SYS-005`–`008`) — and the widget-redaction contract
- **Home Screen widget (`REQ-SYS-005`):** small = one-tap capture (opens
  `EntryRoute.create` per R1's entry-point rule); medium = the last
  reflection's single observation line.
- **Lock Screen widget (`REQ-SYS-006`):** capture, always. "Days since last
  entry" ships **only if** design produces phrasing with no shame valence,
  signed off against the gamification NON-GOAL; otherwise omitted entirely.
  `technology/07` §2's prohibition list is adopted verbatim: no streak
  counters, no scores, no "days since" framed as failure.
- **Control Center control (`REQ-SYS-007`):** `ControlWidget` wrapping R1's
  start-recording intent — the fastest capture path on the device, nearly
  free once the intent exists.
- **Live Activity (`REQ-SYS-008`):** during recording — elapsed time,
  waveform, stop action; Dynamic Island presentation required. This is the
  designed mitigation for silent audio loss (spec 018 R10): **the Live
  Activity and 018's capture-durability contract land as a pair; neither
  ships alone**, and 018's §9.1 device run is not green until both exist.
- **Widget redaction — the requirement, not a nicety:** the last-observation
  widget MUST have a redacted state; no journal content readable on a locked
  screen without authentication, and none in the widget-gallery preview
  (placeholder/snapshot contexts render designed placeholder copy, never real
  entries). `privacySensitive()` is the likely mechanism (🟡, `technology/07`
  §2) — confirm at implementation. Two locks compound here: the device lock,
  and the app lock (spec 023 R6) — a locked *journal* must not leak content
  into widget timelines even on an unlocked device.
- **Data Protection interplay (015 R3, consumed not decided):** whether the
  store is readable while the device is locked is V5's verdict, owned by spec
  015 R3. If `.complete` blocks locked reads, widget timeline refresh happens
  only in unlocked windows and timeline entries are pre-rendered so the
  locked state degrades to redacted-but-present, never to a broken widget.

**Acceptance (Given/When/Then):**
- Given the device locked, when the Lock Screen and any widget are inspected,
  then no journal content is legible — redacted state renders (real-device
  screenshot evidence, both lock types exercised).
- Given the widget gallery open, when the last-observation widget previews,
  then placeholder copy renders, never a real observation.
- Given app lock enabled with the device unlocked, when the medium widget's
  timeline refreshes, then content renders only if the journal is unlocked;
  otherwise the redacted state.
- Given a recording started from the Control Center control, when the user
  leaves the app mid-recording, then the Live Activity shows elapsed time and
  a working stop action in the Dynamic Island (paired 018 R10 run).
- Given the shipped Lock Screen widget, when audited against the NON-GOAL
  list, then no streak, score, or shame-framed count exists anywhere in
  widget copy.

### R5. `DEC-005` — Watch companion in 2.0 or 2.1 (`REQ-SYS-009`, `REQ-SYS-010`) — **OPEN**
This R-block frames the decision and keeps both branches buildable; it does
**not** resolve it. The capability facts are cited, not re-litigated: PCC
**is** available on watchOS 27 (`technology/02` §9 ✅), so Watch-side
reflection is technically possible in some future release; `SpotlightSearchTool`
is **not** available on watchOS (`technology/07` §6 ✅), so retrieval-grounded
features (Ask) stay phone-side under every option.

- **Option A — ship in 2.0:** capture-only companion now (`REQ-SYS-009`):
  on-watch transcription where supported, deferred where not; complication
  for one-tap capture; sync via the shared CloudKit container. *For:* Watch
  capture is the highest-value integration for a voice journal (`REQ-SYS-010`'s
  own framing). *Against:* a second platform target inside a 3-session spec,
  on a pipeline already Xcode-27-gated; `REQ-SYS-010` itself says SHOULD be
  2.1 unless the timeline permits.
- **Option B — defer to 2.1 (the source doc's stated default):** the 2.0
  obligation collapses to "the data layer must not foreclose it" — which is
  already spec 015's design constraint (CloudKit private-DB mirroring, R1/R2;
  cited, not re-decided here). The scope specification `REQ-SYS-010` demands
  *now* is exactly the Option A sentence above — capture-only, complication,
  deferred transcription, shared container — so a 2.1 build forces no schema
  migration. That duty is discharged by this R-block regardless of the
  verdict.

**Acceptance:** the `DEC-005` resolution (A or B, with rationale) is recorded
in this spec's Current State and `ROADMAP.md`'s open-decisions row before
Task 5's branch is taken; if Option B, a one-line confirmation against spec
015's shipped schema (container + entity set support a capture-only Watch
writer without migration) is added here — a checklist read, not new design.

### R6. Focus filter and Shortcuts actions (`REQ-SYS-011`)
- A Focus filter so a "Wind Down" or "Personal" Focus can surface Memento's
  capture prompt. The filter carries configuration only — it MUST NOT embed
  or receive journal content (it is not a `TrustZone`-tagged operation
  because it never touches content; keeping it that way is the requirement).
- Shortcuts actions matching every App Intent — free once R1 exists; the
  audience is small, vocal, and exactly the one that writes about apps.

**Acceptance:** all four intents appear as composable actions in the
Shortcuts app; a user-built automation ("When Wind Down turns on → New
entry") runs end-to-end; the Focus filter's parameter surface, when audited,
contains no entry-content field.

### R7. Design system — Liquid Glass, foldables, haptics (`REQ-SYS-012`–`014`)
- **Liquid Glass (`REQ-SYS-012`):** the single `mementoGlassEffect` wrapper
  (PRES-092, `Utilities/GlassEffectCompat.swift`) is the sole extension
  point — the upgrade already shipped: it internally branches to native
  `.glassEffect` on iOS 26+ honoring tint/interactive, with a material
  fallback. Second-iteration tokens land **inside the wrapper**, never as
  per-view native calls; spec 009 R3's grep criterion (`.glassEffect(` found
  only in `GlassEffectCompat.swift`) stays true afterward. Token names are
  🔴 (V23) — verify against the SDK first. Verified against the
  Reduce Transparency control (see R8; §10.6 makes this part of the
  requirement, not an accessibility afterthought).
- **Foldables (`REQ-SYS-013`):** hinge-state handling in SwiftUI — the API
  surface is 🔴 (V24), verify-first; low effort once confirmed.
- **Core Haptics (`REQ-SYS-014`):** extends PRES-093's existing haptic
  vocabulary (impact on taps/tabs/record, notification haptics on
  success/error) with three designed moments: capture start/stop (a physical
  act, not a UI tap), reflection-ready (distinct, gentle, not an alert), and
  Personal Voice playback begin (🔴 optional — test whether it enhances or
  intrudes, per `technology/09` §5). The system haptics setting is respected;
  haptics never compensate for slow feedback elsewhere.

**Acceptance:** grep confirms one glass system post-token-upgrade; every
glass surface renders legibly under Reduce Transparency (R8's pass covers
this); the three haptic moments fire through the shared vocabulary and are
silent when the system setting disables them; hinge-state handling verified
on the foldable simulator/hardware once V24 closes.

### R8. Accessibility pass (`REQ-A11Y-001`–`003`) — absorbed spec 008, re-run against post-2.0 Views
Spec 008's scope was merged into this spec (013 R6 disposition, `ROADMAP.md`);
its *conventions* are already live in the tree and become the standard for
every post-2.0 surface — its pre-2.0 evidence table is not reused. The
inventory re-runs fresh against spec 019's surfaces plus every surface this
spec adds (widgets, Live Activity, intent dialogs).

- **Dynamic Type through AX5 (`REQ-A11Y-001`):** zero `.system(size:)` on
  text a user reads; each surviving decorative/icon use carries the
  `// icon-size: not user text` comment (008 R1's convention, already live —
  e.g. `Components/OfflineBanner.swift:21`). Layouts absorb AX5 via the
  `// AX5: minHeight` pattern already shipped (`ChatInputField.swift:192`,
  `AddEntryView.swift:223`, `LockScreenView.swift:296`, `WelcomeView.swift:250`)
  — min-height growth, never fixed frames that clip. `Typography.swift`'s
  `relativeTo:` mapping stays canonical (PRES-091, CONSTITUTION §3).
- **VoiceOver (`REQ-A11Y-001`) + Voice Control (`REQ-A11Y-003`):** every
  interactive element gets a meaningful label via
  `Utilities/AccessibilityHelpers.swift`; labels double as Voice Control
  spoken targets. Testability identifiers follow spec 023's shipped
  convention (`welcome.getStarted`, `journal.newEntryFAB`, `drawer.settings`)
  — every new surface extends that namespace; decorative images are
  `.accessibilityHidden(true)`.
- **Reduce Motion (`REQ-A11Y-001`):** the shipped `FABPressStyle` pattern is
  the convention — `@Environment(\.accessibilityReduceMotion)` with the
  animation nil'd (`Components/Buttons/NewEntryFAB.swift:97–102`); all new
  motion (PRES-094's springs, matched-geometry, typewriter) follows it.
- **Increase Contrast + color contrast:** `Theme.swift`'s documented
  WCAG AA/AAA ratios (PRES-090) are the floor; new surfaces meet AA minimum
  and the emotion palette keeps its dark-mode-brightened variants.
- **Reduce Transparency:** required given Liquid Glass (R7) — every
  `mementoGlassEffect` surface must remain legible with transparency reduced.
- **The audio dividend (`REQ-A11Y-002`):** every reflection is
  audio-renderable via spec 018 R7 (cited) — the app is substantially usable
  without reading. The specific obligation this creates here: **VoiceOver and
  TTS reflection playback are tested together** — they share the audio
  channel and must not fight (`technology/09` §6).

**Acceptance (Given/When/Then):**
- Given AX5 text size, when walking the named surfaces (capture composer,
  entry detail, weekly card, Patterns tab, Ask, Settings, lock screen, plus
  this spec's widgets/intent dialogs), then no clipped or overlapping text —
  and `grep -rn "\.system(size:" MeetMemento/ --include="*.swift" | grep -v "icon-size:"`
  returns 0 (008's absorbed guard, re-run post-2.0).
- Given VoiceOver on, when traversing each surface above, then every
  interactive element is announced meaningfully and decorative images are
  skipped (Accessibility Inspector: zero missing-description warnings).
- Given VoiceOver active and reflection playback started, when both produce
  audio, then neither is unintelligible — the explicit shared-channel
  interaction test, on device.
- Given Reduce Motion on, when the FAB, pill nav, and typewriter surfaces
  animate, then motion is suppressed per the `FABPressStyle` convention.
- Given Reduce Transparency on, when every glass surface renders, then text
  contrast still meets AA.
- Given Voice Control on, when the primary actions on each surface are
  addressed by their visible labels, then each activates.

### R9. This spec's §16 verification-queue ownership
This spec owns **§16 item 13 → V20** (per-intent privacy manifest
declarations, R3): **outstanding**. Unblocked by installing the Xcode 27 beta
(standing blocker, not installed) and reviewing the iOS 27 privacy-manifest
documentation; closed — with findings either way — before Tasks 2/3 complete.

Adjacent 🔴 items owned here but not §16-numbered: V21 (journaling domain
schema, R1), V22 (View Annotations — explicitly deferred until after core
surfaces, R1), V23 (Liquid Glass second-iteration token names, R7), V24
(foldable hinge-state APIs, R7). Consumed from their owners, never resolved
here: V1/`DEC-002` via spec 016 R1 (R2's gate); V5 via spec 015 R3 (widget
timeline/background reads, R4). `DEC-005` is this spec's own to resolve (R5)
and is **open**.

## Out of Scope

- Watch app implementation itself, if `DEC-005` defers it to 2.1 — this spec only
  needs to confirm spec 015's data layer doesn't preclude it later.
- Re-litigating spec 008's specific pre-2.0 findings (its exact `.system(size:)`
  call sites, file:line references) — those are stale once Views are rebuilt in
  spec 019; this spec re-runs the inventory fresh rather than importing 008's
  evidence table. (Spec 008 itself is obsolete, fully absorbed here — not a
  separately-still-open backlog.)

## Tasks
- [ ] 1. Resolve `DEC-005` (Watch in 2.0 or 2.1).
- [ ] 2. Implement the four `AppIntent`s + `AppShortcutsProvider` phrases
      (`REQ-SYS-001`).
- [ ] 3. Implement `AppEntity`/`IndexedEntity` conformance for `Entry`
      (`REQ-SYS-002`) — ⚠️ VERIFY item 13.
- [ ] 4. Implement Home Screen widget, Lock Screen widget, Control Center
      control, Live Activity (`REQ-SYS-005`–`008`).
- [ ] 5. If `DEC-005` selects 2.0: implement Watch companion (`REQ-SYS-009`).
- [ ] 6. Implement Focus filter + Shortcuts actions (`REQ-SYS-011`).
- [ ] 7. Apply Liquid Glass 2nd-gen tokens, foldable layout handling, Core
      Haptics (`REQ-SYS-012`–`014`).
- [ ] 8. Full accessibility pass on all new 2.0 surfaces (`REQ-A11Y-001`–`003`).

## Verification
- [ ] **§16 item 13 / V20 — outstanding** (R3/R9): closed-with-findings in
      `technology/11-verification-queue.md` before Tasks 2/3 are checked off.
      Unblocked by: Xcode 27 beta install (standing blocker, not installed) +
      iOS 27 privacy-manifest documentation diff. If the mechanism exists, a
      manifest audit shows every shipped intent declared on-device; if not,
      V20 records that and R3's by-construction note stands.
- [ ] R2's gate held: spec 016 R1's branch declaration line exists before any
      `AppEntity`/`IndexedEntity` commit; real-device system-search behavior
      matches the declared `DEC-002` branch through the App Intents path.
- [ ] App Intents Testing suite green for all four intents (real system
      pathways, no UI automation), including the locked-device test proving
      no journal content in any Siri response while locked.
- [ ] `grep -rn "import Intents\|INIntent" MeetMemento/` → zero app-target
      matches (`REQ-SYS-004`).
- [ ] Widget redaction (R4), real device: locked-device screenshots show the
      redacted state on Lock Screen and Home Screen widgets; widget-gallery
      preview shows placeholder copy; app-lock-enabled timeline shows no
      content while the journal is locked; widget copy audit finds no
      streak/score/shame framing (`REQ-SYS-006` NON-GOAL).
- [ ] Live Activity paired run: spec 018 R10's §9.1 airplane-mode durability
      test executed with the Live Activity live (elapsed time, waveform, stop
      in Dynamic Island) — neither ships alone.
- [ ] `DEC-005` resolution recorded in this spec's Current State and
      `ROADMAP.md` before Task 5's branch is taken; if deferred to 2.1, the
      015 non-foreclosure confirmation line is present (R5).
- [ ] Focus/Shortcuts (R6): four actions composable in the Shortcuts app; a
      Wind-Down automation runs end-to-end; Focus filter parameters carry no
      entry content.
- [ ] Design system (R7): `.glassEffect(` greps only to
      `GlassEffectCompat.swift` after the second-iteration token upgrade
      (V23 closed first); three haptic moments respect the system haptics
      setting; hinge-state handling verified once V24 closes.
- [ ] **Named accessibility passes on every new surface from spec 019 plus
      every surface this spec adds** (R8):
      - **VoiceOver pass** — every interactive element labeled, decorative
        images hidden, Accessibility Inspector zero missing-description
        warnings; includes the VoiceOver × TTS-playback shared-audio-channel
        test on device (`technology/09` §6).
      - **Dynamic Type pass at AX5** — walkthrough screenshots, no
        clipping/overlap; `.system(size:)` grep minus `icon-size:` comments
        → 0.
      - **Reduce Motion pass** — all new motion suppressed per the
        `FABPressStyle` convention (`NewEntryFAB.swift:97–102`).
      - Plus Reduce Transparency on every glass surface (AA contrast holds)
        and an Increase Contrast/WCAG-AA spot check against `Theme.swift`'s
        documented ratios.

## Regression Guards
`CONSTITUTION.md` §2 *Code quality* (Reduce Motion respected, accessibility
labels via shared helper) must extend to every new surface this spec adds, not
regress on the ones spec 008 already covered.
