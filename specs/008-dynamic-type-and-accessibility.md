---
id: 008
title: Dynamic Type and Accessibility Completion
tier: P2
status: not-started
effort: 2 sessions
depends_on: []
findings: [fixed-system-fonts-bypass-dynamic-type, a11y-label-coverage-gaps]
---

# 008 — Dynamic Type and Accessibility Completion

## Why

The design system does this right — `Typography.swift` uses
`Font.custom(_:relativeTo:)` so tokenized text scales with the user's text size. But
**97 raw `.font(.system(size:))` calls** bypass it, many on real body/label text in
Settings and profile-editing screens. Users with larger accessibility text sizes get
fixed, clipped layouts exactly where account management lives. The recent a11y audit
landed labels on 39/151 files; this spec finishes the job on primary flows. App Review
increasingly probes text scaling; beta testers with accessibility needs will hit it
immediately. Gate 3.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.
> Regenerate the inventory first: `grep -rn "\.system(size:" MeetMemento/ --include="*.swift"`

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | 97 `.system(size:)` uses; body-text offenders include `SettingsView.swift:171` (16pt semibold), `:177` (14pt), `EditAboutYourselfView.swift:170,180,188` (15–17pt), `ProfileSettingsView.swift:84` (14pt). Only 14 `ScaledMetric`/`dynamicTypeSize` usages compensate anywhere. | grep inventory | HIGH (body text) / LOW (icons) |
| 2 | A11y labels cover 39/151 files (67 labels, 19 hints, 12 traits) — good on components (JournalCard, chat input, FAB), unaudited on several full screens (onboarding steps, insights detail, settings leaf views). | `MeetMemento/Utilities/AccessibilityHelpers.swift` + audit | MEDIUM |
| 3 | Reduce-motion already respected in 8 components — pattern exists to copy where new animation is touched. | e.g. `SkeletonView.swift` | baseline |

## Requirements

### R1. Body and label text scales with Dynamic Type
**Acceptance:** zero `.system(size:)` on text a user reads (migrated to
`Typography.swift` tokens, adding tokens if a size is genuinely missing);
`.system(size:)` may remain **only** for decorative/iconographic uses
(SF Symbol glyphs sized to containers) — each surviving use gets a
`// icon-size: not user text` comment; Settings, profile editing, onboarding, journal
list/detail, and chat render without truncation or overlap at AX5 text size.

### R2. Layouts tolerate scaling
**Acceptance:** at AX5: no clipped labels, no overlapping controls, scroll views where
fixed frames would truncate; fixed-height containers found during the sweep get
`minHeight`/intrinsic sizing.

### R3. VoiceOver-complete primary flows
**Acceptance:** the five primary flows (onboarding, create entry incl. voice, browse
journal, chat with response + feedback buttons, settings/account) are fully navigable
with VoiceOver: every interactive element has a label; decorative images hidden
(`.accessibilityHidden(true)`); custom controls expose traits/actions (extend the
existing JournalCard pattern).

## Out of Scope

- Localization (all strings hardcoded English) → **spec 012**.
- Color-contrast audit of the theme palette — worth doing but separate; add to
  **spec 012** backlog with the theme tokens as the fix surface.
- New reduce-motion work (already respected; maintain via Regression Guards).

## Tasks

- [ ] 1. Regenerate the `.system(size:)` inventory; classify each hit: user-text
      (migrate) vs icon (comment). (R1)
- [ ] 2. Migrate Settings + profile screens (worst offenders) to Typography tokens. (R1)
- [ ] 3. Migrate remaining user-text hits across Views/Components. (R1)
- [ ] 4. AX5 sweep in simulator (Accessibility Inspector or
      `\.dynamicTypeSize` preview overrides): fix clipping/overlap per R2.
- [ ] 5. VoiceOver pass over the five primary flows; add labels/traits/hidden as
      needed, reusing `AccessibilityHelpers.swift`. (R3)
- [ ] 6. Add `#Preview` variants with `.environment(\.dynamicTypeSize, .accessibility5)`
      to the reworked screens so drift is visible in canvas.

## Verification

- [ ] `grep -rn "\.system(size:" MeetMemento/ --include="*.swift" | grep -v "icon-size:"`
      → 0.
- [ ] Simulator at AX5: walk Settings → Profile → Edit About Yourself → journal list →
      entry detail → chat; screenshot each; no truncation/overlap.
- [ ] VoiceOver on device/simulator through the five flows: every element announced
      meaningfully; feedback thumbs and citations reachable and actionable.
- [ ] Accessibility Inspector audit on main screens: zero "element has no description"
      warnings on interactive elements.

## Regression Guards

- `Typography.swift` is the canonical scaling implementation (CONSTITUTION §3) —
  extend it, don't fork it; custom fonts (Lora/Sora/Manrope) keep their
  `relativeTo:` mappings.
- Reduce-motion support in the 8 components must survive any view edits made during
  the sweep.
- Visual design intent: migrating to tokens should land on the *nearest* token size,
  not redesign screens — diff screenshots at default text size before/after should be
  near-identical.
