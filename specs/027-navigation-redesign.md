---
id: 027
title: Root Navigation Redesign — Whole-Page Paging
tier: P1
status: shipped (2026-08-16) — RootPager / AppHeader / ProfileSheet in tree; contract amended
effort: 1 session
depends_on: [009, 023]
findings: [third-navigation-surface, header-control-ceiling, drawer-owns-horizontal-axis]
pres_refs: [frontend-preservation-contract.md]
---

# 027 — Root Navigation Redesign

**Traceability:** supersedes the pill-nav shell described by **PRES-004** and
**PRES-005**, and removes the left drawer described by **PRES-002**. Completes the
structural cleanup spec 009 began (`deprecated-navigationview`,
`launch-white-flash`) by replacing the shell those specs kept patching. The
drawer's removal is a **sanctioned removal** under the preservation contract §1,
joining account creation (spec 023) as the second.

## Why

Three problems, all structural, none fixable inside the old shell.

**The pills were a third navigation surface.** `TopNav` floated above both pages
as a segmented control, so the app had two competing horizontal navigations: the
pills and the page swipe. They did the same thing, and the pills cost a permanent
strip of vertical space above every screen to say so.

**The shared header capped the app at three controls.** One header floated above
both pages and swapped its trailing button per page. A fourth control pushed the
row past the screen width, and because nothing in the row could compress, it
shifted the entire screen ~12pt off-centre. That ceiling is why "summarize to
entry" lost its slot to chat history rather than both fitting
(`TopNavHeader`'s own comments recorded the collision).

**The drawer owned the horizontal axis app-wide.** `DrawerMenuView`'s interactive
left-edge swipe was attached to the whole `NavigationStack`, so *every* horizontal
drag in the app arbitrated against it. That is irreconcilable with a root pager:
the two gestures cannot share the axis. The drawer was removed rather than hidden
because hiding it leaves the gesture installed.

## Requirements

### R1. Whole-page paging between the two root screens
**Acceptance:** `RootPager` pages full-bleed between `.journal` and `.chat`, built
on `TabView` + `.page(indexDisplayMode: .never)` — chosen for interruptible,
rubber-banded, velocity-aware paging and per-page state preservation that a
hand-rolled `DragGesture` only approximates. A light impact haptic fires when the
page commits, whether swiped or tapped (`RootPager.swift:82-86`), preserving
**PRES-004**'s swipe-progress haptics and **PRES-093**'s haptic vocabulary.
`RootPage` replaces `JournalTopTab`, whose `title` strings existed only to label
the pills.

### R2. Mirrored corner icons replace the pills
**Acceptance:** each page carries a one-tap equivalent of the swipe, in the corner
facing its destination so the two agree directionally — Journal's top-right chat
icon goes to Chat, Chat's top-left book icon comes back. The icon is not a
separate navigation; it is the swipe's shortcut.

### R3. Per-page headers
**Acceptance:** `AppHeader` is attached by each page via
`.safeAreaInset(edge: .top)`, so the page reserves exactly the height the header
occupies. The three views that hardcoded `safeAreaTop + 8 + 44 + 32` to guess
another view's geometry are gone. Each page carries only its own controls, which
dissolves the three-control ceiling. The header owns its status-bar clearance
explicitly (`AppHeader.swift:52-60`) because every root surface is deliberately
full-bleed, so no ambient safe area survives to sit in.

### R4. Profile sheet replaces the drawer — **sanctioned removal of PRES-002**
**Acceptance:** `ProfileSheet`, presented from the Journal header's avatar
(`JournalView.swift:230`), carries "About yourself", "Your journal themes", and
Settings. It runs its own `NavigationStack` so rows push in place and swipe-back
works without losing the sheet.

**What is preserved:** every drawer *destination* (**PRES-003**).
`DrawerRoute.aboutYourself` and `.journalGoals` remain routed
(`ContentView.swift:392-398`); `EditAboutYourselfView` and `EditJournalGoalsView`
would be orphaned otherwise, as they have no other entry point.

**What is removed:** the drawer *interaction* itself (**PRES-002**) — the 280pt
slide-out, the 40pt left-edge swipe zone, tap-outside-to-close, and the
content-slides-right animation. This is a deliberate behavioral removal, not a
reimplementation: a sheet is not a drawer. It is sanctioned because the edge
gesture and root paging cannot coexist on the same axis, and root paging is the
primary navigation.

**Invariant:** nothing else in the app may own a horizontal edge drag while the
pager is on screen.

### R5. Contract amendments
**Acceptance:** **PRES-002** marked as sanctioned removal citing this spec;
**PRES-003** repointed at `ProfileSheet.swift`; **PRES-004** and **PRES-005**
amended for the pager and per-page headers; the §4 reuse ledger and **ATTACH-05**
updated where components were consumed.

## Non-goals

- Liquid Glass adoption on the new chrome — that is its own workstream;
  `AppHeader` inherits the `GlassEffectContainer` pattern but the material
  decision and **PRES-092** live there.
- Restoring a drawer in any form. The horizontal axis belongs to the pager.
- The third Patterns tab (**ATTACH-03**), which assumed the pill shell and needs
  rethinking against paging before spec 019 claims it.

## Acceptance

- [x] `RootPager` pages between both root screens with commit haptics.
- [x] `AppHeader` attached per page via `safeAreaInset`; no hardcoded header-height
      arithmetic remains.
- [x] `ProfileSheet` reaches About yourself / journal themes / Settings.
- [x] `TopNavHeader`, `TopTabNav`, `DrawerMenuView`, `DrawerMenuItem` deleted with
      no code references remaining (comments only).
- [x] Debug build green, unit tests pass.
- [ ] Device pass: paging feel, corner-icon direction, header clearance on a
      notched device, light + dark.

## Regression Guards

- **PRES-003** — every drawer destination must remain reachable; `ProfileSheet` is
  now their only entry point.
- **PRES-004 (amended)** — swipeable root navigation and its commit haptic survive;
  only the pill affordance is gone.
- **PRES-093** — haptic vocabulary intact (`RootPager.swift:84`).
- **PRES-094** — motion respects Reduce Motion; paging is system-driven.
- **ATTACH-03** — the third-tab plan predates this shell; re-evaluate before 019.
