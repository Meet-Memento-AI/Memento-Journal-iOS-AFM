# Experience Profile — QA evidence

Environment note: this cloud agent host cannot run `xcodebuild` / iOS Simulator.
The quality bar below is covered by automated unit tests plus static path
verification. Physical-device AFM generation remains a Gate α / device check.

## Quality bar

| Check | Evidence |
|---|---|
| Dual-profile lean (different themes → different questions/focus, same L0 facts) | `ExperienceProfileBuilderTests.test_dualProfile_differentThemes_differentPromptLeanAndStarters` |
| AFM unavailable still completable | `ThemeConfirmationView` keyword/browse fallback; `test_rebuildLens_fallsBackToKeywordsWhenUnavailable` |
| Settings explainability (“How Memento is tuned for you”) | `EditJournalGoalsView.tuningSummary` + `settings.tuningLens` / `settings.rebuildLens` |
| Delete everything clears profile | `AppStateStore.deleteEverything` → `LocalProfileStore.clearAll()`; `test_deleteEverything_clearsExperienceProfile` |
| Closed vocabulary | `ThemeCatalog.validate` + builder tests stripping unknown ids |
| Chat starters themed | `ThemeAwareChatStarters` + `AIChatView.rotateSuggestions` |
| Legacy YourGoalsView removed | File deleted; onboarding uses `ThemeConfirmationView` only |

## Manual device follow-ups (human)

1. Onboarding with Apple Intelligence available → suggested chips from reflection.
2. Onboarding with Intelligence off → browse catalog → complete to main app.
3. Settings → Themes → Rebuild lens updates the tuning summary copy.
4. Insights empty state shows theme-flavored starters after profile exists.
