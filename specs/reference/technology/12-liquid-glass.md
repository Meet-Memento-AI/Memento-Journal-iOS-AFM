# 12 — Liquid Glass (SwiftUI `glassEffect`)

> **ACTIVE — re-adopted 2026-08-16** (see PRES-092). Glass was adopted by spec
> 024, removed on 2026-08-07 for rendering "poorly / doubled", and re-adopted once
> that verdict was traced to two fixable causes rather than the material. The
> removal was judged in the **Simulator**, where glass renders flat gray by
> design, and spec 024's own device pass (Task 7) was never completed.
>
> **The two causes, and the rules that follow from them:**
>
> 1. **An opaque scrim behind the chrome.** `ScrollEdgeFade(.top)` is opaque for
>    its first 75% and was painted directly behind the floating header, so glass
>    had nothing but a flat colour to refract. → **Never put an opaque fill or
>    scrim beneath glass.** Use `scrollEdgeEffectStyle(_:for:)` instead — `.hard`
>    when a soft fade leaves a hazy band under the chrome.
> 2. **Adjacent glass with no shared sampling region.** Glass cannot sample glass.
>    → **One `GlassEffectContainer` per adjacent cluster**, `spacing` matching the
>    layout's own spacing (spec 024 passed `0`, which merges nothing). Never nest
>    containers.
>
> **Third rule, learned during re-adoption:** apply `.glassEffect` to the view
> that **contains** the content, never as a sibling `.background(...)`. Only
> content composited inside the effect receives the system's vibrancy treatment;
> outside it, glyphs keep their literal token colour and wash out.
>
> Current usage: `.regular` only, untinted, navigation layer only — content
> surfaces (list rows, cards, the crisis card) stay flat.

**Read when:** applying, changing, or reviewing any Liquid Glass surface — nav
bars, pills, FABs, cards, input fields, listening panels.

**Primary source:** Apple — *Applying Liquid Glass to custom views*
`https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views`
(quoted below; ✅ VERIFIED against that page and compile-checked against the
iOS 27.0 SDK with Xcode 27 beta 4 on 2026-08-07).

The deployment target is **iOS 26.0**, so the native API is **always available**.
There is no availability gate, no `#if canImport(FoundationModels)` guard, and no
material fallback for glass anywhere in the app.

---

## 1. Applying the effect — `glassEffect(_:in:)`

✅ VERIFIED

```swift
func glassEffect(_ effect: Glass = .regular, in shape: some Shape = .capsule) -> some View
```

- Default variant is `.regular`; default shape is `Capsule`.
- **Apply `.glassEffect` last** — after every modifier that changes the view's
  appearance (padding, background, clip). It composites the glass under the
  content.

```swift
Text("Hello").padding().glassEffect()                       // regular, capsule
Text("Hello").padding().glassEffect(in: .rect(cornerRadius: 16))
Text("Hello").padding().glassEffect(.regular.tint(.orange).interactive())
```

Applying it to a **bare shape** (`Circle().glassEffect(.clear, in: Circle())`)
renders that shape as glass — the shape's default fill does not show through on
device. **Do not** put an opaque `.fill(...)` under a glass surface to "back" it:
that reads as a flat panel and defeats the glass. `.regular` glass already
supplies a frosted legibility backing.

## 2. The `Glass` type

✅ VERIFIED (`.regular`, `.tint`, `.interactive`); 🟡 LIKELY (`.clear`)

- `Glass.regular` — the standard frosted material. Reads as a light translucent
  fill over content.
- `Glass.clear` — transparent glass: refraction and a specular edge, no frost.
  Not shown on the doc page but present in the iOS 27 SDK (compiles).
- `.tint(Color)` — suggest prominence with a color that reads *through* the glass.
- `.interactive()` — touch/pointer reactivity: "the same responsive and fluid
  reactions that `PrimitiveButtonStyle.glass` provides to standard buttons."

Chain them: `.regular.tint(theme.primary).interactive()`.

## 3. Glass buttons — `.buttonStyle`

✅ VERIFIED

- `.buttonStyle(.glass)` — the idiomatic way to give a `Button` glass. Prefer it
  over hand-applying `.glassEffect` to a shape behind a tap target.
- `.buttonStyle(.glassProminent)` — a prominent, saturated tinted-glass button
  for primary actions (FAB, primary CTA). Combine with `.tint(color)` and
  `.buttonBorderShape(.circle)` / `.capsule` for the shape.

```swift
Button { … } label: {
    Image(systemName: "square.and.pencil").frame(width: 64, height: 64)
}
.buttonStyle(.glassProminent)
.buttonBorderShape(.circle)
.tint(theme.primary)
```

## 4. Grouping — `GlassEffectContainer`

✅ VERIFIED

```swift
GlassEffectContainer(spacing: 0) { HStack { … } }
```

> "Use `GlassEffectContainer` when applying Liquid Glass effects on multiple
> views to achieve the best rendering performance. A container also allows views
> with Liquid Glass effects to blend their shapes together and to morph in and
> out of each other during transitions."

**Spacing rule:** the larger the container `spacing`, the sooner neighbors blend.
> "A spacing value on the container that's larger than the spacing of an interior
> `HStack`/`VStack` … causes Liquid Glass effects to blend together at rest."

So for controls that should stay visually separate at rest (a nav row of avatar
+ pill + action button), use a **small** container spacing (`0`) — they only
merge while overlapping. For controls you *want* to merge/morph, use a larger
spacing.

## 5. Morphing — `glassEffectID` and `glassEffectUnion`

✅ VERIFIED

- `glassEffectID(_:in: namespace)` (with `@Namespace`) — stable identity so
  SwiftUI morphs the same glass shape across appear/disappear. Use inside a
  `GlassEffectContainer`.
- `glassEffectUnion(id:namespace:)` — merge multiple same-shape effects into one
  unified glass shape (dynamic / `ForEach` groups).
- **`matchedGeometryEffect` interplay:** for a single glass element that just
  *moves* between positions (e.g. the tab pill), `matchedGeometryEffect` is a
  valid, simpler choice and is what this app uses (preservation contract
  PRES-004). Do not stack `glassEffectID` on top of a `matchedGeometryEffect`
  element for the same movement.
- **Transitions:** `.matchedGeometry` (default, near neighbors) vs `.materialize`
  (effects farther apart than the container spacing).

## 6. Performance budget

✅ VERIFIED

> "Creating too many Liquid Glass effect containers and applying too many effects
> to views outside of containers can degrade performance. Limit the use of Liquid
> Glass effects onscreen at the same time."

Group related effects in one container; don't scatter loose effects.

## 7. Accessibility

🟡 LIKELY — confirm on device (`REQ-SYS-012`, see `09-ui-swift6-testing.md` §3).

Native glass adapts to system settings, but verify:
- **Reduce Transparency** — glass should degrade to a more opaque surface.
- **Reduce Motion** — morph/interactive transitions should quiet down.
- **Increase Contrast** — edges/legibility hold.

## 8. Simulator caveat

The iOS Simulator has historically rendered `glassEffect` poorly (flat neutral
gray). Removing opaque under-fills mitigates the worst of it, and the iOS 27
simulator renders it far better than earlier ones — but **the real device is the
acceptance surface** for any Liquid Glass visual judgment. Never reintroduce an
opaque material approximation to "fix" the simulator.

## 9. How Memento uses it (call-site map)

Native `.glassEffect` is used directly in the view files (there is no wrapper):
- **Clear interactive glass** (translucent controls): icon/avatar buttons
  (`AvatarInitialButton`, `IconButtonNav`, `NarrateButton`, `TopNavHeader` icon,
  `AddEntryView` icon/date), the tab pill (`TopTabNav`), listening panel
  (`ListeningPanel`), chat-history "new" pill (`ChatHistorySheet`).
- **Regular glass** (frosted surfaces): chat input bar (`ChatInputField`),
  settings section cards (`SettingsView`, `AppearanceSettingsView`,
  `AboutSettingsView`, `DataUsageInfoView`), chat-history cards
  (`ChatHistoryItem`), drawer settings button (`DrawerMenuView`), mic FABs
  (`AddEntryView`, `EditAboutYourselfView`, `LearnAboutYourselfView`).
- **Prominent tinted glass** (primary actions): new-entry FAB (`NewEntryFAB`,
  `.glassProminent`), submit button (`AddEntryView`), active-chat action button
  (`TopNavHeader`).
- **Container:** `TopNavHeader` groups its three glass controls in a
  `GlassEffectContainer(spacing: 0)`.

Theme tokens: `theme.glassFill` is the subtle tint for `.regular` surfaces;
`theme.glassBorder` is a decorative hairline on **non-glass** insight cards. The
old `theme.glassFallback` token was removed with the material fallbacks.
