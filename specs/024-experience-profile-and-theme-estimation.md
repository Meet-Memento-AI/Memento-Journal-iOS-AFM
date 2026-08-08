# 024 — Experience Profile and Theme Estimation

## Intent

Personalize Memento per user during onboarding by turning the
`LearnAboutYourself` reflection into a local **Experience Profile**: confirmed
one-word themes from a closed **ThemeCatalog**, plus an optional bounded prompt
lens. The core companion prompt (L0) stays immutable; personalization appends an
L1 section only.

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
  UserDefaults. No accounts, no sync.
- **R6 Prompt composition.** Ask prompts use version suffix `+p2` when an
  ExperienceProfile is present. Summary ignores personalization. Personalization
  never affects stance, retrieval, or citations.
- **R7 Settings parity.** Theme editor writes the same profile. Editing themes
  clears a stale lens until rebuilt.
- **R8 Legacy migration.** Pre-catalog goal strings map through
  `ThemeCatalog.legacyGoalMapping`.

## Catalog

`ThemeCatalog.catalogVersion = themes@1` — bundled one-word journaling themes
grouped by `ThemeFamily`.
