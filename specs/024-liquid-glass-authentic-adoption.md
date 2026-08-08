---
id: 024
title: Authentic Liquid Glass Adoption
tier: P1
status: superseded (2026-08-07) — R1–R5 shipped, but Liquid Glass was then removed entirely (see the superseding note below); the app no longer uses `.glassEffect`.
effort: 1 session
depends_on: [009]
findings: [dual-glass-systems, glass-hardcoded-values]
source_refs: [REQ-SYS-012]
tech_refs: [technology/12-liquid-glass.md, technology/09-ui-swift6-testing.md]
pres_refs: [frontend-preservation-contract.md]
---

# 024 — Authentic Liquid Glass Adoption

> **SUPERSEDED 2026-08-07 — Liquid Glass removed.** Shortly after this adoption
> landed, Liquid Glass was rendering poorly and showing stacked/double-glass in
> practice, so it was **removed entirely** and replaced with a flat `#fafafa`
> surface fill at every site (prominent brand actions — new-entry FAB, submit,
> active-chat action — keep their purple fill). The `theme.glassFill` token was
> also removed; `theme.glassBorder` remains for non-glass insight-card strokes.
> The native `.glassEffect` / `.buttonStyle(.glassProminent)` / `GlassEffect
> Container` API is no longer used anywhere in the app. The API reference in
> `reference/technology/12-liquid-glass.md` is kept for historical/context value
> only. Everything below documents the (now-reverted) adoption.

**Traceability:** completes spec 009 R3 ("one glass system") by reversing its
*mechanism*: instead of consolidating on the `mementoGlassEffect` wrapper, the app
now uses Apple's native Liquid Glass API directly. Grounded in the Apple doc
*Applying Liquid Glass to custom views* and captured durably in
`reference/technology/12-liquid-glass.md`.

## Why

The deployment target is **iOS 26.0**, so native `.glassEffect` is *always*
available — yet every glass surface went through a wrapper
(`Utilities/GlassEffectCompat.swift`) whose whole job was to branch on an
availability that can never be false, plus a Simulator special-case and a
material fallback. Around that wrapper, call sites accumulated hard-coded
approximations that fight real glass: opaque fills layered *under* glass (so it
read as a flat panel), hand-rolled specular/sheen gradients, and dead code. This
spec removes all of it and adopts the authentic API, so the UI reads as genuine
Liquid Glass on device and the code matches the current SwiftUI documentation.

## Technology References

- `reference/technology/12-liquid-glass.md` — the full authentic API (this
  spec's implementation guide): `glassEffect(_:in:)`, `Glass` variants,
  `GlassEffectContainer`, `glassEffectID`/`glassEffectUnion`, glass button styles,
  the "never layer opaque fills under glass" rule, and the simulator caveat.
- `reference/technology/09-ui-swift6-testing.md` §3 — `REQ-SYS-012` accessibility
  requirement (Reduce Transparency / Motion / Increase Contrast).

## Current State (evidence)

> Audited 2026-08-07 (pre-migration state). Line numbers rot — re-verify.

| # | Problem | Evidence | Severity |
|---|---|---|---|
| 1 | All glass routed through a wrapper whose iOS-26 gate can never be false on a 26.0-target app; also special-cased the Simulator and kept a material fallback | `Utilities/GlassEffectCompat.swift` (native call gated by `#if canImport(FoundationModels)` + `#available(iOS 26.0, *)` + `#if targetEnvironment(simulator)`) | MEDIUM |
| 2 | Opaque fills layered *under* glass → reads as a flat panel, defeats the glass | `ChatInputField` (`.fill(theme.glassFallback.opacity(0.9))`), Settings cards (`.fill(white/gray)` + heavy fake white tint), `DrawerMenuView`/`ChatHistoryItem`/`AddEntryView`/`Edit`/`LearnAboutYourself` (`.fill(Color.white.opacity(0.3))`) | HIGH |
| 3 | Hand-rolled specular/sheen gradients faking glass | `TopNavHeader` active-chat action button, `AddEntryView` submit button (`LinearGradient(white .25→.05→clear)` + edge stroke) | MEDIUM |
| 4 | Dead code: unused `glassLikeEffect` material extension | `Views/AI-Chat/AIChatView.swift` (no call sites) | LOW |
| 5 | Availability gating + `fallback*Background` duplicates across 5 files | `NewEntryFAB`, `DrawerMenuView`, `ChatHistoryItem`, `EditAboutYourselfView`, `LearnAboutYourselfView` | MEDIUM |

## Requirements

### R1. Remove the wrapper; use native glass directly
**Acceptance:** `GlassEffectCompat.swift` is deleted. No `mementoGlassEffect` and
no `fallback*Background` remain. Native `.glassEffect(_:in:)` (and glass button
styles) appear directly in the view files. No `#if canImport(FoundationModels)` /
`#available(iOS 26.0, *)` / `#if targetEnvironment(simulator)` guard wraps any
glass. `grep -rn "mementoGlassEffect" MeetMemento/` → 0.

### R2. No opaque fills or hand-rolled sheens under glass
**Acceptance:** no `.fill(...)` sits beneath a `.glassEffect` surface; the
specular/sheen `LinearGradient` overlays are gone. Translucent surfaces use
`.clear`/`.regular` glass; prominent actions use a **tint** that reads through the
glass, not a solid fill. `grep -rn "Glassy sheen" MeetMemento/` → 0.

### R3. Full adoption of the idiomatic API
**Acceptance:** the primary FAB uses `.buttonStyle(.glassProminent)`; the
`TopNavHeader` glass-control row is wrapped in a `GlassEffectContainer`. The
`TopTabNav` sliding pill keeps `matchedGeometryEffect` (PRES-004) with a native
glass fill — it is **not** converted to `glassEffectID` (single moving element;
converting would risk the preserved interaction).

### R4. Theme-token hygiene
**Acceptance:** the now-unused `theme.glassFallback` token is removed (both
palettes). `theme.glassFill` (glass tint) and `theme.glassBorder` (non-glass card
hairline) remain, with updated doc comments.

### R5. Documentation
**Acceptance:** `reference/technology/12-liquid-glass.md` captures the authentic
API; `00-INDEX.md`, `technology/09` §3, spec 009 R3, and PRES-092 are amended to
point at native-direct adoption.

### R6. Visual + accessibility verification
**Acceptance:** on a **real device** (glass renders as translucent, not flat
gray) in light+dark, every migrated surface reads as Liquid Glass; behavior is
correct under Reduce Transparency, Reduce Motion, and Increase Contrast
(`REQ-SYS-012`).

## Out of Scope

- Converting the `TopTabNav` pill or `ChatInputField` `matchedGeometryEffect`
  animations to `glassEffectID` morphing (PRES-004 preserves the pill interaction).
- Redesigning which surfaces *are* glass (settings-card-as-glass is an existing
  product choice; this spec only makes the rendering authentic).
- The `.ultraThinMaterial` keyboard-blur overlay in `AIChatView` (not a glass
  control; legitimately a material).

## Tasks

- [x] 1. Delete `Utilities/GlassEffectCompat.swift` and the dead `glassLikeEffect`
      extension in `AIChatView.swift`. (R1, R4-adjacent)
- [x] 2. Migrate glass buttons: `AvatarInitialButton`, `IconButtonNav`,
      `NarrateButton`, `TopNavHeader` icon, `AddEntryView` icon/date → native
      `.glassEffect(.clear.interactive(), in:)`; `NewEntryFAB` →
      `.buttonStyle(.glassProminent)` (drop gating + gradient fallback). (R1, R3)
- [x] 3. Migrate surfaces; remove opaque under-fills: `ChatInputField`,
      `ChatHistoryItem`, `ChatHistorySheet`, `ListeningPanel`, `DrawerMenuView`,
      Settings cards (`SettingsView`/`AppearanceSettingsView`/`AboutSettingsView`/
      `DataUsageInfoView`), `AddEntryView` mic FAB + submit, `TopNavHeader`
      active action, `EditAboutYourselfView`, `LearnAboutYourselfView`. Delete the
      `#available` scaffolding + `fallback*Background`. (R1, R2)
- [x] 4. `TopTabNav` pill → native glass fill, keep `matchedGeometryEffect`; wrap
      `TopNavHeader` glass row in `GlassEffectContainer(spacing: 0)`. (R3)
- [x] 5. Remove `theme.glassFallback`; update Theme token comments. (R4)
- [x] 6. Write `technology/12-liquid-glass.md`; amend `00-INDEX`, `technology/09`,
      spec 009 R3, PRES-092, and the CI comment. (R5)
- [ ] 7. Device visual + accessibility pass. (R6)

## Verification

- [x] `grep -rn "mementoGlassEffect" MeetMemento/ --include="*.swift"` → 0.
- [x] `grep -rn "fallback.*Background\|glassLikeEffect\|glassFallback" MeetMemento/ --include="*.swift"` → 0.
- [x] `grep -rn "Glassy sheen" MeetMemento/ --include="*.swift"` → 0.
- [x] No glass wrapped in `targetEnvironment(simulator)` / iOS-26 availability guards.
- [x] Debug build green: `DEVELOPER_DIR=<Xcode 27 beta> xcodebuild -scheme MeetMemento -destination "platform=iOS Simulator,name=iPhone 17" -configuration Debug build` → **BUILD SUCCEEDED**, 0 errors, no new warnings from touched files.
- [ ] Real-device visual pass (light+dark): nav row, tab pill, FAB, chat input, settings cards, mic FABs, listening panel read as translucent Liquid Glass, not flat gray.
- [ ] Reduce Transparency / Reduce Motion / Increase Contrast degrade gracefully.

## Regression Guards

- **PRES-004** — the `matchedGeometryEffect` sliding glass pill must keep sliding;
  do not convert it to `glassEffectID`.
- **PRES-007** — the FAB stays a prominent floating action (now `.glassProminent`).
- **PRES-090** — Theme token system: `glassFill`/`glassBorder` semantics preserved;
  only the dead `glassFallback` removed.
- **PRES-092** — "one glass system" still holds (now native-direct).
- CONSTITUTION §3 tokens remain the single source for color/radius.
