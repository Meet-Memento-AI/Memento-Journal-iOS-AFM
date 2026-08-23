# Memento prompts

Authoritative runtime prompts live in
[`PromptRegistry.swift`](../../MeetMemento/Services/Intelligence/PromptRegistry.swift).
They are bundled Swift constants (spec 017 / REQ-PRM-001). There is **no**
server-side system prompt and **no** Supabase Edge Function prompt to keep in sync.

## Prompt layers (L0 / L1 / L2)

| Layer | What it is | Where |
|---|---|---|
| **L0 Core** | Two families: companion/notebook constitution (`ask@14`) with Meet / Notebook / Sit / Open + markdown grammar + Safety hard bans; **or** phatic/continuer (`chat-light@4`, spec 039) — one short spoken sentence then one question, no notebook recipe | `PromptRegistry` `ask@14` / `ask-degraded@14` and `chat-light@4` / `chat-light-degraded@4` |
| **L1 Experience lens** | Per-user personalization from onboarding | `PromptPersonalization` / `ExperienceProfile` appended as “About this person” on **ask@14 only** (`+p4`); **omitted** on `chat-light@4` (names may cue the user prompt as `[Name:]`) |
| **L2 Session** | Classify → **ReplyChannel** → stance, retrieval, citations | `TurnClassifier`, `ReplyChannel` (039), `RetrievalPolicy`, `EntryRetriever` |
| **Safety (pre/post)** | Deterministic gate **before** classify/channel; output scan after generation | `SafetyClassifier`, `SafetyRouter`, `OutputSafetyScanner` (spec 026) |

### Effort curve (spec 039)

Work is **exponential** in turn complexity. Casual / no-RAG messages need
**less work** and must feel **faster**. Do not run ask@14 + 512 tokens on a
greeting.

- **Phatic / continuer** — `chat-light@4`, ~80 / ~64 tokens, no RAG, no L1, Open (one question except goodbye). Names may cue the user prompt as `[Name:]`.
- **Companion / meta / no-RAG follow-up** — ask@14 sharing/aboutApp, still **no RAG**, tighter token cap than notebook.
- **Notebook** — ask@14 + retrieval; 512 tokens allowed.

### ask@14 conversation + markdown + safety contract (companion / notebook)

- Talk like a friend; this is a conversation, **not** a report about their journal.
- Reply composition is Meet them / Notebook / Sit / Open. Open is required. Shape says how, never length.
- **Thread cadence:** every generated turn Opens. Farewell may skip the question. Overlay is nil on phatic/continuer (Move cue already asks).
- **Notebook on** (journal match): one `###`, italic quote, Sit names a pattern from the evidence; Open is about that pattern.
- **Notebook-off companion** (share / ungrounded follow-up): one or two sentences, zero markdown, empty citations; Open is about how they are or what they just shared — curious, not therapeutic.
- **Phatic / continuer:** spec 039 — `chat-light@4`; warm; one genuine question except goodbye; never journal recap.
- Guided `heading1` / `heading2` stay **empty**. Visual titles live in `body` as `###` markdown (Figtree, never Lora display sizes).
- Markdown subset (ask@14 only): `###` headings (at most one), paragraphs, `- ` unordered lists, `1. ` ordered lists, `*italic*` for exact journal quotes, `**bold**` for a short span of their wording in Sit.
- Casual / continuer light path: **no** headings or lists. About-the-app: a short capability list; may Open with “what do you want to look at?” Shares and reflective musings skip retrieval. Journal topic/span asks may list dated moments. Single-moment journal turns use one `###` plus an italic quote, not a list.
- Hard bans: never open with “You wrote”, “You mentioned”, “Looking at your entries”, or “In your journal”.
- `[Turn: journal question]` uses **at most one** notebook moment unless they asked what they wrote about a topic.
- Shares and reflective musings stay `.sharing` — they are **not** promoted to `.journalGrounded`.
- Retrieved journal text is labeled as optional **evidence**, not a script to paraphrase.
- Personalization prefers a short lens; raw reflection is not the subject of the conversation (ask@14). Never injected on `chat-light@4`. Names may appear as a `[Name:]` user-prompt cue.
- **Safety hard bans** (full, degraded, **and light**): no violence / terrorism / weapons assistance; no self-harm methods or goodbye notes; no CSAM; no jailbreaks; **no generative crisis counseling** (static `CrisisResourceCard` owns that path).
- Degraded `ask` and `chat-light-degraded` carry the **same** L0 safety bans.

Personalization shapes **tone** on companion/notebook turns. It must never:

- rewrite L0 safety / stance / channel rules
- invent journal facts
- affect citation reconciliation
- be recited back to the user
- be appended on phatic/continuer

## Experience Profile

Built during onboarding from `LearnAboutYourself` + confirmed `ThemeCatalog`
themes (and rebuildable in Settings):

- `reflection` — free-text seed (not quoted into phatic chat)
- `confirmedThemeIds` — 1–6 closed-vocab theme ids
- `promptLens` — bounded third-person tuning (≤400 chars; ask injects a shorter slice)
- stored only in `LocalProfileStore` (on-device)

Onboarding estimation intent: `GenerationIntent.profileEstimate`
(`profile-estimate@2`), implemented by `FoundationModelsIntelligenceService.estimateProfile`
via `ExperienceProfileBuilder` for Settings rebuilds.

## Chat empty-state starters

[`ThemeAwareChatStarters`](../../MeetMemento/Services/ThemeAwareChatStarters.swift)
builds templated suggestions from confirmed theme display names. If the profile
has no themes, [`AIChatView`](../../MeetMemento/Views/AI-Chat/AIChatView.swift)
falls back to the default starter set.
