---
id: 033
title: Neural Voice Catalog and Picker
tier: P1
status: not-started — roster fixed at four by owner decision 2026-08-18 (DEC-011/DEC-012); descriptors pending the V30 audition
effort: 1 session
depends_on: [030, 031]
findings: [picker-replacement-migration-path, character-not-gender-presentation, live-previews-replace-prerendered-clips, three-settings-route-resolution-sites, compact-voice-nudge-retirement]
source_refs: [REQ-TTS-006, REQ-TTS-003, REQ-VOX-001, DEC-009, DEC-011]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
pres_refs: [frontend-preservation-contract.md]
---

# 033 — Neural Voice Catalog and Picker

**Traceability:** implements `REQ-TTS-006` over the bundled style vectors from
`specs/030-neural-tts-model-assets.md` R4 and the free switching guaranteed by
`specs/031-neural-synthesis-engine.md` R4. **Resolves `DEC-011`** (yes — the
neural catalog replaces the system-voice picker) and **owns `DEC-009`** and V30.
Amends `REQ-VOX-001`'s user-facing half and retires
`specs/029-performance-and-speech-excellence.md` R8's compact-voice nudge.

## Why

Because voices are style vectors rather than models, switching is instant and
free — and the UI must not pretend otherwise. There is no loading state to show,
because there is nothing to load.

The harder decision is presentation. A voice roster whose internal identifiers
are gendered (`F1`, `M3`) invites a picker organised by gender, which is the
wrong axis for this product: a journaling companion is chosen by how it feels to
be spoken to — warm, bright, measured, steady — not by a demographic label. The
gendered ids stay internal, and the user sees character.

This spec also carries the migration nobody will notice if it works and everybody
will notice if it doesn't: a shipped picker, a shipped preference key holding an
`AVSpeechSynthesisVoice.identifier`, and a shipped UI test all assume the old
world.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §5 — voice processing and
  why the roster is auditioned through it (V30, `DEC-009`).
- `specs/reference/technology/06-speech-and-audio.md` §B2 (amended 2026-08-18) —
  the system-voice ranking, now a fallback mechanism rather than a user choice.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | A system-voice picker already ships at the route this spec must take over | `MeetMemento/Views/Settings/VoiceSettingsView.swift` — nav title "Read Aloud", `AVSpeechSynthesisVoice` list + "Speaking Speed"; reached via `SettingsRoute.voice` (`MeetMemento/Models/Routes.swift:36`) | High — replacement, not greenfield |
| 2 | `SettingsRoute` destinations are resolved in **three** places; adding or repointing a route means editing all three | `MeetMemento/ContentView.swift:324`, `MeetMemento/Views/Journal/JournalView.swift:451`, `MeetMemento/Components/Settings/ProfileSheet.swift:162` — each has its own `case .voice:` | Medium — easy to half-do |
| 3 | The persisted preference holds an `AVSpeechSynthesisVoice.identifier`, which will resolve to nothing in the new catalog | `MeetMemento/Services/PreferencesService.swift:22` key `selectedVoiceIdentifier`, `:58` `@Published var selectedVoiceIdentifier: String?`, `:102` read at init | High — every existing user has one set or nil |
| 4 | A UI test asserts the current picker's structure and rate persistence | `MeetMementoUITests/VoiceSettingsUITests.swift::test_voiceSettings_reachable_andRateSelectionPersists`; identifiers `settings.voice.automatic` (`VoiceSettingsView.swift:63`), `settings.voice.option.<identifier>` (`:74`), `settings.voice.rate.<name>` (`:87`), `settings.voice.downloadHelp` (`:50`) | High — breaks unless identifiers are planned |
| 5 | A compact-voice nudge points users at system-voice downloads they will no longer be choosing | `AIChatView.voiceNudgeBanner`; `PreferencesService.swift:24` `compactVoiceNudgeDismissed`; spec 029 R8 | Medium — becomes actively wrong advice |
| 6 | Speaking Speed ships today and is user-visible | `MeetMemento/Models/SpeechRatePreset.swift` — slower/normal/brisk/fast; `PreferencesService.swift:23` `speechRate`, default `.brisk` | Medium — removing a shipped control is a regression |

## Requirements

**Traceability:** R1 → `REQ-TTS-006`; R2 → `REQ-TTS-006` (previews); R3 →
`REQ-TTS-006` + `DEC-011` (persistence and migration); R4 → `REQ-TTS-006`
(mid-session switching); R5 → `DEC-011` (presentation); R6 → `REQ-TTS-003`
(pre-download state); R7 → `DEC-009` / V30.

**Zone declaration:** `.z0Device`. Voice selection reads bundled resources and
writes a local preference. Per `REQ-TTS-001` it makes **no network call** — named
explicitly because a picker that fetches a voice list or a preview is the easiest
way to violate this family's central rule without noticing.

### R1. `VoiceCatalog` is the single source of truth (`REQ-TTS-006`)

One type maps internal style ids → display name, character descriptor, style-vector
resource, and turn-start mask clip (spec 032 R3). Previews are **not** a catalog
field — they are synthesized live (R2). Adding, removing, or reordering a voice is a
**catalog edit only** — no branching in views, no per-voice code anywhere else.

This matters more than it looks: `DEC-009` may change the roster after the
audition (R7), and a roster change must not become a refactor.

Switching carries no engine cost (031 R4). The catalog MUST NOT introduce one —
no eager preloading per voice, no spinner, no artificial delay to make the change
feel substantial.

**Acceptance (Given/When/Then):**
- Given a voice removed from the catalog, when the app builds and runs, then no
  other file changed and the picker renders the remaining voices.
- Given a voice selected, when the switch is instrumented, then overhead is
  **< 10 ms** and **no reload event** is logged (031 R4 is the engine-side
  guarantee; this is the user-facing measurement).

### R2. Previews are synthesized live (`REQ-TTS-006`)

> **Reversed 2026-08-18 (`DEC-012`).** This requirement previously mandated
> build-time preview clips, for two reasons: they had to work *before the download
> completed*, and live synthesis would pay first-load latency. **Bundling removes
> the first reason entirely**, and shipping pre-compiled `.mlmodelc` (030 R2)
> removes most of the second.

Previews are synthesized on demand, in the selected voice, at the user's **current
speaking rate**. That is strictly better than a rendered clip: a build-time render
is frozen at whatever rate it was made with, so it drifts out of sync the moment
someone changes the Speaking Speed preference — and the preview's entire job is to
answer "what will this sound like *for me*."

It also deletes a build step and a staleness class: no clip pipeline, nothing to
re-render when the model or roster changes.

**Warm on appearance.** `VoiceSettingsView` appearing is a voice-intent signal in
exactly the sense `031` R3 means, so the engine warms then — not on first tap.

*Turn-start mask clips (`032` R3) remain pre-rendered.* Those must sound
instantly at turn start, which is the one case synthesis cannot serve.

**Acceptance (Given/When/Then):**
- Given the picker opened, when a voice is tapped, then a preview plays in that
  voice with no perceptible load delay (engine warmed on appear).
- Given the Speaking Speed preference changed, when a preview is played, then it
  uses the **new** rate — the case a pre-rendered clip could never get right.
- Given a fresh install with **no network ever**, when previews are played, then
  they work; there is nothing to fetch.

### R3. Persistence and migration — a stale id resolves silently (`DEC-011`)

Selection persists as the neural style id, via the existing `PreferencesService`
pattern (`UserDefaults`; the app has no SwiftData and no `@AppStorage`).

On load, the persisted value is validated against the catalog. **An unrecognised
id resolves to the default voice with no error UI.** Three distinct cases must
all land there:

1. A legacy `AVSpeechSynthesisVoice.identifier` from the shipped picker (e.g.
   `com.apple.voice.enhanced.en-US.Evan`) — every existing user who ever chose a
   voice has one of these.
2. `nil`, meaning "Automatic" in the old world — the common case.
3. A neural id retired by a future roster change (`DEC-009`).

No alert, no "your voice is no longer available" message. The user picked a voice
once; they get a good voice now. Explaining a migration they did not ask for is
worse than performing it quietly.

Whether to reuse the `selectedVoiceIdentifier` key or introduce a new one is the
implementer's call, but the **fallback behavior above is not** — and the old key
must be cleaned up either way, including in `PreferencesService.resetToDefaults()`.

**Acceptance (Given/When/Then):**
- Given a persisted legacy system-voice identifier, when the app launches, then
  the default neural voice is selected, no alert appears, and no crash occurs.
- Given a persisted id retired by a roster change, when the app launches, then
  same result.
- Given "delete everything", when it runs, then voice preferences reset with the
  rest (`resetToDefaults()`).

### R4. Mid-session switching applies from the next chunk (`REQ-TTS-006`)

A switch during active narration takes effect at the **next chunk boundary** —
never mid-utterance, which would splice two voices inside one sentence. No reload
UI, no spinner, no artificial delay.

**Acceptance:** given narration in flight, when the voice is changed, then the
current chunk finishes in the old voice and the next chunk speaks in the new one,
with no audible gap beyond the normal inter-chunk seam.

### R5. Character, not gender (`DEC-011`)

The picker presents **character descriptors** as the primary label — the vocabulary
comes from the audition (R7), e.g. warm / bright / measured / steady. Internal
gendered ids never surface in the UI, and there are **no male/female section
headers**.

This is a product decision, recorded so it is not relitigated as a styling
preference: the axis a person chooses a journaling companion on is tone, and
offering gender as the organising principle invites a choice about the wrong
thing.

VoiceOver announces the character descriptor and the option plays its preview —
the screen must be usable, and a *voice picker* especially must be usable, without
sight.

**Acceptance (Given/When/Then):**
- Given the picker, when audited, then no user-visible string contains a gender
  label and no section is organised by one.
- Given VoiceOver, when each option is focused, then the descriptor is announced
  and the preview is playable — UI test.

### R6. There is no pre-model state left to design for (`REQ-TTS-003`)

> **Superseded 2026-08-18 (`DEC-012`).** This requirement described a picker that
> had to render, preview and accept selections while a 148 MB download was still
> in flight — passive download indicator, selection applied later, and so on.
> **None of that state exists.** The model is in the binary; the picker opens with
> a working engine behind it on first launch, in airplane mode, always.

What survives from the original intent is the part that was never really about
downloading: **the picker must never nag.** The retired compact-voice banner and
the "How to download a voice" row are both deleted (`029` R8, amended; `030` R5).
A user opening this screen chooses a voice and hears it. They are told nothing
about assets, quality tiers, or what they could have if they went elsewhere.

**Acceptance:** given a fresh install with no network, when the picker is opened,
then four voices render and each previews on tap — and no row, banner, or
subtitle anywhere mentions downloading, quality tiers, or system voices.

### R7. This spec's decision and verification-queue ownership (`DEC-009`, V30)

Owns **V30**: audition every candidate voice **through the voice-processing (AEC)
path**, on a physical device, using real journal-reflection passages.

Auditioning through the degraded path rather than the clean one is the entire
point. Voice processing thins and nasalizes output (`technology/13` §5), so a
voice chosen on hi-fi playback and shipped into conversation is a voice chosen
under the wrong conditions. If a candidate degrades, the roster is swapped
**now** — a voice users have bonded with cannot be replaced cheaply later.

A scratch harness suffices; this does **not** wait for spec 034 to ship the real
conversation path. Per CONSTITUTION rule 10, preview and mask clips are not
rendered for a roster V30 has not confirmed — rendering them early is how a
provisional roster becomes permanent by accident.

**Acceptance:** V30 updated with the audition outcome and `DEC-009` resolved in
writing, before preview and mask clips are rendered for the shipping roster.

## Non-goals

- Assets, download, and bundling mechanics — spec 030.
- Engine-side switching cost — spec 031 R4.
- The turn-start mask's playback behavior — spec 032 R3 (this spec owns only the
  catalog entry pointing at the clip).
- User-facing speech-rate redesign. **The shipped "Speaking Speed" section
  stays** — see the note below.
- Personal Voice. `REQ-VOX-002`/`003` remain gated on V6 and unaffected; if V6
  ever closes positive, Personal Voice re-enters as a catalog entry rather than as
  a separate screen, which is exactly why R1 insists the catalog is the only
  source of truth.
- Onboarding or paywall gating. Neither exists for voice today and none is added.

> **Note on speech rate.** The design that motivated this family specified "no
> user-facing rate UI in this release." That was written for a greenfield app.
> Memento **already ships** a Speaking Speed control (`SpeechRatePreset`,
> `PreferencesService.speechRate`) with a UI test asserting its persistence.
> Removing a shipped control is a regression regardless of what a design document
> preferred, so the section stays and its presets map onto the engine's rate
> parameter (spec 035 R5 owns the defaults). If it is ever removed, that is its
> own decision with its own record — not a side effect of a voice change.

## Acceptance

1. **Device, airplane mode, fresh install:** picker renders all voices with
   playable previews and a passive download indicator.
2. **Device:** selecting each voice changes the next utterance's voice; measured
   switch overhead **< 10 ms** with no reload event logged.
3. **Device:** mid-narration switch applies at the next chunk, not mid-sentence.
4. **Unit:** legacy `AVSpeechSynthesisVoice.identifier`, `nil`, and a retired
   neural id all resolve to the default with no alert; `resetToDefaults()` clears
   voice state.
5. **UI test:** Settings → Read Aloud reachable; selection persists across
   launch; VoiceOver announces character descriptors; **updated**
   `VoiceSettingsUITests` and `TTSReadAloudUITests` green.
6. **Audit:** no gender label in any user-visible string; no compact-voice nudge
   anywhere.
7. **V30 closed** and `DEC-009` resolved in writing before clips are rendered.

## Regression Guards

- **All three `SettingsRoute` resolution sites** updated together
  (`ContentView.swift`, `JournalView.swift`, `ProfileSheet.swift`). Editing one
  produces a screen that works from Settings and not from the journal drawer —
  a bug that reads as random.
- **Existing accessibility identifiers** (`settings.voice`,
  `settings.voice.option.<id>`) are preserved in shape so the shipped UI tests
  survive with minimal, intentional edits. Renaming them silently converts a
  regression test into a passing test that checks nothing.
- **Spec 029 R8's voice ranking** stays — it selects the fallback voice.
  `AVSpeechSynthesisVoice.speechVoices()` stays off the main thread.
- **Spec 018 R7 / `REQ-VOX-001`** — the fallback path still resolves the best
  Enhanced/Premium voice. This spec removes the *choice*, not the *quality rule*.
- **CONSTITUTION rule 12 / `REQ-TTS-001`** — no network from the picker, including
  previews and voice enumeration.
- **`frontend-preservation-contract.md`** — the Settings section/row composition
  (`SettingsSection`, `SettingsSelectableRow`) is reused, not reinvented.

## Appendix — interface sketch

```swift
/// Single source of truth (R1). Adding or removing a voice is an edit here only.
struct VoiceCatalog {
    struct Entry: Identifiable {
        let id: String            // internal style id — never rendered (R5)
        let displayName: String   // character-led, e.g. "Warm"
        let descriptor: String    // one line of character, not demographics
        let previewClip: URL      // bundled, build-time rendered (R2)
        let maskClip: URL         // bundled; same id keys synthesis (032 R3)
    }

    static let all: [Entry]
    static let `default`: Entry

    /// Unknown / legacy / retired ids resolve to `default`, silently (R3).
    static func resolve(persistedID: String?) -> Entry
}
```
