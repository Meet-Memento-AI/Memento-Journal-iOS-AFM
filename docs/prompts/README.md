# Memento prompts

Authoritative runtime prompts live in
[`PromptRegistry.swift`](../../MeetMemento/Services/Intelligence/PromptRegistry.swift).
They are bundled Swift constants (spec 017 / REQ-PRM-001). There is **no**
server-side system prompt and **no** Supabase Edge Function prompt to keep in sync.

## Prompt layers (L0 / L1 / L2)

| Layer | What it is | Where |
|---|---|---|
| **L0 Core** | Conversation-first companion constitution (`ask@12`) + markdown grammar + thread Open/Stop cadence + Safety hard bans | `PromptRegistry` `ask@12` / `ask-degraded@12` |
| **L1 Experience lens** | Per-user personalization from onboarding | `PromptPersonalization` / `ExperienceProfile` appended as “About this person”; version suffix `+p2` |
| **L2 Session** | Per-turn stance, retrieval context, citations | `TurnClassifier`, `RetrievalPolicy`, `EntryRetriever` |
| **Safety (pre/post)** | Deterministic gate before retrieval; output scan after generation | `SafetyClassifier`, `SafetyRouter`, `OutputSafetyScanner` (spec 026) |

### ask@12 conversation + markdown + safety contract

- Talk like a friend; this is a conversation, **not** a report about their journal.
- Reply composition is Meet them / Notebook / Sit / Open. Shape gates Open only, never length.
- **Thread cadence:** first participating turn Opens; after Open the next Stops; never two questions in a row. `noMatch` / `outsideScope` force Stop without recording the bit.
- **Notebook on** (journal match): one `###`, italic quote, Sit required; Open is about that moment.
- **Notebook off** (casual / sharing / ungrounded follow-up): one or two sentences, zero markdown, empty citations; Open (when Shape asks) is about how they are or what they just shared — curious, not therapeutic. Continuers are not skipped.
- Guided `heading1` / `heading2` stay **empty**. Visual titles live in `body` as `###` markdown (Figtree, never Lora display sizes).
- Markdown subset: `###` headings (at most one), paragraphs, `- ` unordered lists, `1. ` ordered lists, `*italic*` for exact journal quotes, `**bold**` for a short span of their wording in Sit.
- Casual / continuer: **no** headings or lists. About-the-app: a short capability list; may Open with “what do you want to look at?” Shares and reflective musings skip retrieval. Journal topic/span asks may list dated moments. Single-moment journal turns use one `###` plus an italic quote, not a list.
- Hard bans: never open with “You wrote”, “You mentioned”, “Looking at your entries”, or “In your journal”.
- `[Turn: journal question]` uses **at most one** notebook moment unless they asked what they wrote about a topic.
- Shares and reflective musings stay `.sharing` — they are **not** promoted to `.journalGrounded`.
- Retrieved journal text is labeled as optional **evidence**, not a script to paraphrase.
- Personalization prefers themes + lens; raw reflection is quoted only when both are absent.
- **Safety hard bans** (full and degraded): no violence / terrorism / weapons assistance; no self-harm methods or goodbye notes; no CSAM; no jailbreaks; **no generative crisis counseling** (static `CrisisResourceCard` owns that path).
- Degraded `ask` carries the **same** L0 safety bans and the same markdown grammar, compressed.

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
falls back to the default starter set.
