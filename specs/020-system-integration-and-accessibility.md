---
id: 020
title: System Integration and Accessibility
tier: P2
status: not-started
effort: 3 sessions
depends_on: [019]
findings: []
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

- [ ] TODO (derive from source doc §10, per its §17 checklist): `AppIntent`/
  `AppShortcutsProvider` contracts for the four intents in `REQ-SYS-001`; `Entry`
  conformance to `AppEntity`/`IndexedEntity` with `EntityQuery` (`REQ-SYS-002`) —
  ⚠️ VERIFY item 13 (privacy manifest declarations for intent routing); confirm
  no SiriKit code is added (`REQ-SYS-004`); widget/Control/Live Activity contracts
  (`REQ-SYS-005`–`008`, noting `REQ-SYS-006`'s "omit if it can't be phrased
  without shame" constraint against gamification NON-GOALs); Watch scope decision
  — resolve `DEC-005` (2.0 vs. 2.1) before deciding whether `REQ-SYS-009`/`010`
  are built now or merely kept from blocking the data layer later; Focus/
  Shortcuts (`REQ-SYS-011`); design system items (`REQ-SYS-012`–`014`); full
  accessibility pass superseding spec 008 (obsolete) — re-run its
  `.system(size:)`/VoiceOver inventory against post-2.0 Views rather than reuse
  its stale pre-2.0 evidence (`REQ-A11Y-001`–`003`).

  Additions from the technology library:
  - **Widget privacy**: the last-observation widget MUST have a redacted state —
    no journal content readable on a locked screen without authentication
    (`technology/07` §2; `privacySensitive()` is the likely SwiftUI mechanism).
    This is the widget-scale instance of `DEC-002`'s visibility concern.
  - **`IndexedEntity` donation shares `DEC-002`'s verdict** (`technology/07`
    §1): entity-schema donation feeds the same semantic index the search tool
    reads; spec 013's R1 verdict covers this path too — do not implement
    `REQ-SYS-002` before that verdict lands.
  - **watchOS capability split, for `DEC-005`** (`technology/02` §9,
    `technology/03` header): PCC **is** available on watchOS 27 but
    `SpotlightSearchTool` is **not** — so Watch-side reflection is technically
    possible later, while retrieval-grounded features (Ask) stay phone-side.
    The 2.0 obligation is unchanged: design the data layer so a 2.1 Watch app
    forces no migration.
  - **Verification tooling**: use the App Intents Testing framework (✅ verified
    — validates through real system pathways without UI automation) for every
    intent this spec ships; VoiceOver and TTS reflection playback must be
    tested *together* — they share the audio channel and must not fight
    (`technology/09` §6).

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
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include item 13 of the source doc's §16 verification queue marked
      confirmed or outstanding, and a VoiceOver/Dynamic Type/Reduce Motion pass
      on every new surface from spec 019.

## Regression Guards
`CONSTITUTION.md` §2 *Code quality* (Reduce Motion respected, accessibility
labels via shared helper) must extend to every new surface this spec adds, not
regress on the ones spec 008 already covered.
