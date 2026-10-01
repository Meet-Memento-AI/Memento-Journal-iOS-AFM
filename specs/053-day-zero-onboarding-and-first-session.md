---
id: 053
title: Day-0 Onboarding and First Session
tier: P1
status: not-started (2026-09-26) — derived from the Monetization Strategy (September 2026), DEC-013
effort: 3 sessions
depends_on: [021, 023, 038, 019, 020]
findings:
  - trial-offer-has-no-first-value-moment
  - onboarding-ends-on-an-empty-journal
  - paywall-reachable-only-from-locked-surfaces
source_refs: [DEC-013, DEC-001, REQ-MON-001, REQ-MON-003, REQ-SUR-002, REQ-SUR-004, REQ-SYS-006, REQ-DATA-004]
pres_refs: [PRES-060, PRES-061, PRES-062, PRES-063, PRES-064, PRES-065, PRES-066, PRES-007, PRES-020, ATTACH-07, ATTACH-08]
---

# 053 — Day-0 Onboarding and First Session

**Traceability:** implements section 1 ("Onboarding, Day 0") of the Monetization
Strategy (September 2026), as recorded in spec 021's DEC-013 decision record.
This spec owns the first-run flow from Welcome to the journal. Spec 021 owns
the paywall's content and the offer rules. Spec 019 owns the chat and
notifications. Spec 020 owns the widget.

**Mints:** `REQ-ONB-001`…`REQ-ONB-007`.

**Amends** (dated blocks written in each file, 2026-09-26): the preservation
contract PRES-061, PRES-063 and ATTACH-07/08; 023 R3; 038's persistence note.

**Does not implement:** streaks, shareable cards, or a trial-reminder push
notification. These are architecture NON-GOALs (`memento-2.0-architecture-spec.md`
line 90), and DEC-013 keeps them out. Email capture and analytics are also out
(spec 023, `REQ-MON-004`).

## Why

The strategy offers Pro once, on Day 0, **after Memento has responded to
the user's first entry**. (There is no free trial, per DEC-014: the free tier
is the trial.) The reasoning is that the offer lands when the user
has just seen what the AI does with their own words, not before.

Today, onboarding ends on an empty journal (023 R3). The only way to reach the
paywall is to hit a locked surface (021 R4), so no one sees the offer at the
moment it makes the most sense.

## Current State (evidence)

| Area | Today | Source |
|---|---|---|
| Step order | Name → Learn about yourself → Themes → app lock → loading | `OnboardingCoordinatorView.swift:16-23`, PRES-061 |
| First entry | None. Onboarding ends on an empty journal with **Write your first entry** | 023 R3, PRES-063, 038 |
| Chat in onboarding | None | — |
| Paywall | Only on locked surfaces. **Switched ON** (`RevenueCatConfig.isPaywallEnabled = true`, 2026-09-30) | 021 R4, `ProGate.swift` |
| Notifications | Two in total: an opt-in daily reminder (off by default) and weekly-ready. Never requested in onboarding | 019 R8, `NotificationServiceTests.test_exactlyTwoIdentifiers` |
| Lock Screen widget | A view (`MementoLockWidgetView`) with **no WidgetKit extension target** | 020 R4, `project.pbxproj` |

## Requirements

### R1. `REQ-ONB-001` — step order
The step order becomes:

Welcome → Name → **Quiz** → app lock → **First entry** → **First chat** →
**Paywall** → **Daily reminder** → **Widget** → Journal

- Name (PRES-062) and app lock (PRES-065, default-on with an explicit-friction
  skip) are unchanged.
- The quiz replaces "Learn about yourself" and the theme chips (PRES-063 and
  PRES-064; see R2).
- Every step after the first entry can be skipped in one tap, and none of them
  blocks reaching the journal.
- Back from the first step still returns to Welcome.
- **Reduced tier (DEC-001):** on a device without Apple Intelligence, the
  First chat and Paywall steps are **not presented**. The flow goes
  First entry → Daily reminder → Widget. This follows the same
  `ProAccess.decide` rule as everywhere else, evaluated when the step would
  appear.

**Acceptance:**
- Given a `.full` device, when onboarding completes, then the steps occur in
  the order above.
- Given a `.reduced` device, when onboarding completes, then no chat step and
  no paywall step is ever presented (UI test with a stubbed tier).

### R2. `REQ-ONB-002` — the quiz (3–4 questions)
The quiz has three questions, plus an optional fourth:

1. **Why do you want to journal?** Single choice, with an "Other" option.
2. **What's on your mind lately?** Multi-select topic chips from the
   existing ThemeCatalog, plus optional free text.
3. **When would you like to write?** Morning, midday, evening, or "no set
   time".
4. **(Optional) Anything you'd like Memento to know?** Free text.

How the answers are used:
- Answers persist **locally only**, in `LocalProfileStore` and
  `ExperienceProfile`, exactly as the free text and themes did before (PRES-063
  and PRES-064's storage is unchanged).
- Question 2's chips seed theme estimation. The drawer's "Rebuild lens" still
  edits them later.
- Question 3's answer sets the daily-reminder time offered in R6. Choosing it
  does **not** turn the reminder on.
- Answers are never written as a journal entry. They never leave the device,
  and they never cross into Z2 (CONSTITUTION §4 rule 8). None of them is sent
  to RevenueCat.

### R3. `REQ-ONB-003` — the first entry is written by the user
- One writing prompt is chosen **deterministically** from the quiz answers,
  from a bundled table keyed by the answers to questions 1 and 2. It is **not
  generated**: no model call, Z0.
- The prompt is seeded into the preserved composer (PRES-023) the same way a
  Journaling Suggestion is (ATTACH-10). This is one prompt, not a template
  picker, so 019 R1's "no mode selector, no template picker" audit still
  passes.
- **The user writes the entry.** Onboarding never creates or saves an entry
  on the user's behalf (018 R4, "no ghostwriting"). Voice capture works as it
  does everywhere else.
- Skipping writing goes straight to the journal. It skips First chat and
  Paywall too, because there is nothing for the chat to respond to. Pro is
  then first offered at the first re-offer moment (021 R9).

**Acceptance:**
- Given a completed quiz, when the first-entry step opens, then the composer
  holds exactly one prompt and no text.
- Given the user saves, then exactly one entry exists, whose body is what
  they wrote.

### R4. `REQ-ONB-004` — the first chat
- The chat opens on the entry just written, in the free chat scope (019 R5
  amendment: the current entry plus the current conversation).
- Memento's first message asks **one specific question grounded in that
  entry**. It follows the archivist posture (`REQ-SUR-002`): it may quote or
  name something the user wrote and ask what happened next or what they
  meant. It does not advise, diagnose, comfort, or reassure.
- This is the user's free chat, and its messages count toward the free daily
  limit (021 R4).
- The safety classifier runs first (026 R4). A crisis-adjacent entry gets the
  static resource card (`REQ-SUR-004`), and the flow **skips the paywall
  step**: no purchase offer ever follows a crisis card.
- A **Continue** control is always visible. The user moves on when they
  choose, after at least one assistant reply or on skip.

**Acceptance:**
- Given a first entry, when the chat opens, then the first assistant turn
  cites that entry and ends in a question.
- Given crisis-adjacent text, then the card shows and the next step is Daily
  reminder, not Paywall.

### R5. `REQ-ONB-005` — the onboarding paywall (presentation only)
- This is the **only full-screen offer on Day 0**. It counts toward 021 R9's
  limit of one a day.
- The content is owned by spec 021 R10 (as amended by DEC-014, no free
  trial): two pages titled "This is just the beginning." The primary action
  is **Upgrade for {price} a year** (or a month), and **Continue free** is a
  clearly visible secondary action.
- **Continue free** and **Subscribe** both lead to R6. The flow is the same
  whichever the user picks.
- It presents only when `ProAccess.decide` returns `.showPaywall` (R1 covers
  the Reduced tier).

### R6. `REQ-ONB-006` — daily reminder opt-in
- A page framed as the user's **daily writing reminder**, at the time from
  question 3 (editable on the page). It has **Turn on reminder** and **Not
  now**.
- The system permission prompt appears **only after** the user taps Turn on.
  This keeps 019 R8's "opt-in, off by default" intact: nothing is on unless
  the user chose it.
- This is the existing `memento.dailyReminder` notification. **No new
  notification identifier is added**, and the two-identifier audit still
  holds.

### R7. `REQ-ONB-007` — Lock Screen widget setup
- One page that shows how to add the Lock Screen capture widget (020 R4,
  `REQ-SYS-006`: capture only, redacted when locked, no streak or count).
- **Blocked on 020 R4's WidgetKit extension.** Until that target ships, the
  step is not presented. It is feature-flagged off, not shipped as a dead
  instruction.
- The page ends onboarding: its primary action opens the Journal, showing the
  first entry.

## Out of Scope
- Streaks, streak moments, shareable insight cards, and any notification
  beyond the two (DEC-013, architecture NON-GOALs).
- Email collection, analytics events, and attribution SDKs (spec 023,
  `REQ-MON-004`, 021 R11).
- Paywall content, prices, and trial rules (spec 021 R10).
- Building the widget extension (spec 020 R4).

## Tasks
- [ ] 1. Replace `LearnAboutYourselfView` and `ThemeConfirmationView` in the route
      enum with a `QuizView` (R2). Keep `saveExperienceProfile` as the sink.
- [ ] 2. Bundled prompt table and chooser (R3). Unit test: every answer
      combination maps to a prompt.
- [ ] 3. First-entry step reusing the composer with a seeded prompt (R3).
- [ ] 4. First-chat step: open Ask on the new entry's ID in the free scope,
      with the grounded opening question (R4).
- [ ] 5. Onboarding paywall step hosting 021 R10's paged paywall (R5).
- [ ] 6. Daily-reminder opt-in page (R6). Keep the notification audit green.
- [ ] 7. Widget setup page behind a flag, until 020 R4 ships (R7).
- [ ] 8. Update 023 R3's acceptance UI test to the new end state.

## Verification
- The UI test walks the full flow on `.full` and on stubbed `.reduced`.
- `NotificationServiceTests.test_exactlyTwoIdentifiers` still passes.
- An airplane-mode walkthrough reaches the Journal. On `.full` the paywall
  shows its offline state.
- 023 R7's manual walkthrough is re-run with the new steps.

## Regression Guards
- PRES-060 (Welcome), PRES-062 (name), PRES-065 (app lock) and PRES-066
  (completion) are unchanged.
- The quiz answers never become an entry. The only entry is the one the user
  writes.
- No paywall is reachable on a `.reduced` device, or after a crisis card.
