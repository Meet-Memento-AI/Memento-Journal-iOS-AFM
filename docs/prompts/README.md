# Memento prompts

Authoritative runtime prompts live in
[`PromptRegistry.swift`](../../MeetMemento/Services/Intelligence/PromptRegistry.swift).
They are bundled Swift constants (spec 017 / REQ-PRM-001). There is **no**
server-side system prompt and **no** Supabase Edge Function prompt to keep in sync.

## Prompt layers (L0 / L1 / L2)

| Layer | What it is | Where |
|---|---|---|
| **L0 Core** | Conversation-first companion constitution (`ask@4`) | `PromptRegistry` `ask@4` / `ask-degraded@4` |
| **L1 Experience lens** | Per-user personalization from onboarding | `PromptPersonalization` / `ExperienceProfile` appended as “About this person”; version suffix `+p2` |
| **L2 Session** | Per-turn stance, retrieval context, citations | `TurnClassifier`, `RetrievalPolicy`, `EntryRetriever` |

### ask@4 conversation contract

- Talk like a friend; this is a conversation, **not** a report about their journal.
- Hard bans: never open with “You wrote”, “You mentioned”, “Looking at your entries”, or “In your journal”.
- `[Turn: journal question]` may use **at most one** entry reference; multi-entry dumps only when the user asks what they wrote about a topic.
- Shares and reflective musings stay `.sharing` — they are **not** promoted to `.journalGrounded`.
- Retrieved journal text is labeled as optional **evidence**, not a script to paraphrase.
- Personalization prefers themes + lens; raw reflection is quoted only when both are absent.

Personalization shapes **tone and which questions to ask**. It must never:

- rewrite L0 safety / stance rules
- invent journal facts
- affect citation reconciliation
- be recited back to the user

## Experience Profile

Built during onboarding from `LearnAboutYourself` + confirmed `ThemeCatalog`
themes (and rebuildable in Settings):

- `reflection` — free-text seed (quoted into ask only as fallback)
- `confirmedThemeIds` — 1–6 closed-vocab theme ids
- `promptLens` — bounded third-person tuning (≤400 chars)
- stored only in `LocalProfileStore` (on-device)

Onboarding estimation intent: `GenerationIntent.profileEstimate`
(`profile-estimate@1`), implemented by `FoundationModelsIntelligenceService.estimateProfile`
via `ExperienceProfileBuilder` for Settings rebuilds.

## Chat empty-state starters

[`ThemeAwareChatStarters`](../../MeetMemento/Services/ThemeAwareChatStarters.swift)
builds templated suggestions from confirmed theme display names. If the profile
has no themes, [`AIChatView`](../../MeetMemento/Views/AI-Chat/AIChatView.swift)
falls back to the generic `AISuggestionPrompts.json` pool.

## Related docs

- Spec: [`specs/024-experience-profile-and-theme-estimation.md`](../../specs/024-experience-profile-and-theme-estimation.md)
- Stance contract tests: `PromptStanceSyncTests`, `AskPromptContractTests`
- Personalization tests: `PromptPersonalizationTests`, `ExperienceProfileBuilderTests`
- Conversation policy tests: `ConversationFlowTests`, `RetrievalPolicyTests`
