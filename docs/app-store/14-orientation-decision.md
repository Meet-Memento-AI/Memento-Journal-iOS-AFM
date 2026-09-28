# 14 — Orientation decision (1.x)

**Decided 2026-09-26.** iPhone is **portrait-only** for 1.x. iPad keeps
**all four orientations**.

## What ships

| Device | Setting (`withMemento.xcodeproj/project.pbxproj`, Debug + Release) | Value |
|---|---|---|
| iPhone | `INFOPLIST_KEY_UISupportedInterfaceOrientations` | `UIInterfaceOrientationPortrait` |
| iPad | `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` | Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight |

## Why

iPhone landscape would mean re-proving `RootPager`, the `AddEntryView` glass,
the editor backdrop, and `ContentColumnMetrics.maxWidth` (600pt is a no-op on
portrait phones only because no phone is wider than 440pt — see
`ContentColumnTests`). That is a second layout, not polish, and it is out of
scope for 1.x.

## Rules that follow

- Listing copy, screenshots, previews, and review notes must **not** show or
  imply iPhone landscape. iPhone shots are portrait (see
  `04-metadata-and-assets.md`); iPad may show either orientation.
- Changing the iPhone value is a product decision: update this file, the
  comment on `ContentColumnMetrics`, and `ContentColumnTests` in the same PR.
