# 038 — Experience Profile and Theme Estimation

## Intent

Personalize Memento per user during onboarding by turning the
`LearnAboutYourself` reflection into a local **Experience Profile**: confirmed
one-word themes from a closed **ThemeCatalog**, plus an optional bounded prompt
lens. The core companion prompt (L0) stays immutable; personalization appends an
L1 section only. Chat empty-state starters surface the themes so uniqueness is
visible, not only hidden inside prompts.

## Requirements

- **R1 Closed vocabulary.** AFM may only return ThemeCatalog ids. Unknown ids
  are stripped in Swift via `ThemeCatalog.validate`.
- **R2 Human confirm.** ThemeConfirmationView proposes; the user confirms or
  edits before continue. Never silently lock a persona.
- **R3 Caps.** Max 6 confirmed themes. Default 4 suggestions. Reflection ≤ 300
  chars in ask prompts; lens ≤ 400 chars.
- **R4 Fallback.** If AFM is unavailable or fails, use keyword overlap against
  catalog synonyms, then browse-all. Onboarding must still complete offline.
- **R5 Local only.** ExperienceProfile persists in `LocalProfileStore` /
  UserDefaults. No accounts, no sync. Delete-everything clears the profile.
- **R6 Prompt composition.** Ask prompts use version suffix `+p2` when an
  ExperienceProfile is present. Summary ignores personalization. Personalization
  never affects stance, retrieval, or citations.
- **R7 Settings parity.** Theme editor and About Yourself write the same
  profile. **Rebuild lens** re-runs estimation while preserving confirmed themes
  (unless the user explicitly re-suggests).
- **R8 Legacy migration.** Pre-catalog goal strings map through
  `ThemeCatalog.legacyGoalMapping`.
- **R9 Visible uniqueness.** Chat empty-state starters prefer templated prompts
  derived from confirmed theme display names, with generic fallback.

## Catalog

`ThemeCatalog.catalogVersion = themes@1` — bundled one-word journaling themes
grouped by `ThemeFamily` (164 themes).

## Prompt layers

| Layer | Source | Mutable per user? |
|---|---|---|
| L0 Core | `PromptRegistry` `ask@4` | No — companion constitution |
| L1 Lens | ExperienceProfile via `PromptPersonalization` | Yes — reflection, themes, lens |
| L2 Session | Stance + retrieval + citations | No personalization influence |

## Persistence timing

The Experience Profile is persisted when the user confirms themes (before
security setup). The first journal entry is created after security in
`finishSecuritySetup`, still from the LearnAboutYourself reflection.

## Acceptance criteria

### Onboarding estimate + confirm
- **Given** a non-empty LearnAboutYourself reflection and AFM available  
  **When** ThemeConfirmationView appears  
  **Then** it shows a loading state, then preselects ≤4 validated catalog themes, and Continue requires 1–6 selections.
- **Given** AFM unavailable  
  **When** ThemeConfirmationView estimates  
  **Then** keyword overlap or browse-all is shown and onboarding can still complete.
- **Given** empty reflection  
  **When** ThemeConfirmationView appears  
  **Then** the full catalog is browsable with no forced preselection.

### Prompt composition
- **Given** a stored ExperienceProfile with themes and lens  
  **When** an ask prompt is resolved  
  **Then** version ends with `+p2` and the “About this person” section includes themes and lens, never recited instructions.
- **Given** personalization present  
  **When** summary instructions are resolved  
  **Then** version stays `summarize@1` with no About section.

### Settings rebuild
- **Given** confirmed themes and a reflection  
  **When** the user taps Rebuild lens or saves About Yourself  
  **Then** `ExperienceProfileBuilder` updates `promptLens` / suggestions and preserves confirmed theme ids.
- **Given** Delete everything  
  **When** `AppStateStore.deleteEverything` runs  
  **Then** ExperienceProfile and personalization accessors are empty.

### Chat starters
- **Given** confirmed themes `stress`, `clarity`  
  **When** chat empty-state rotates suggestions  
  **Then** at least one starter mentions those themes (templated).
- **Given** no confirmed themes  
  **When** suggestions rotate  
  **Then** the generic prompt pool is used.

### Closed vocabulary
- **Given** an estimate returning unknown ids  
  **When** results are validated  
  **Then** unknown ids are dropped and the count never exceeds the configured max.

## Non-goals

- Soft retrieval bias / theme-filtered RAG
- Remote/OTA ThemeCatalog or prompt manifest
- Per-user rewrite of L0
- Therapeutic framing, scores, streaks, social, accounts
