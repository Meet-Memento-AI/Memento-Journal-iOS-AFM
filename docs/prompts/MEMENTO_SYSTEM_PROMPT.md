# Memento system prompt (DEPRECATED)

**Do not use this file as the runtime source of truth.**

Authoritative Ask / summarize / profile-estimate instructions live in:

[`MeetMemento/Services/Intelligence/PromptRegistry.swift`](../../MeetMemento/Services/Intelligence/PromptRegistry.swift)

(currently `ask@6` / `ask-degraded@6`).

See [`docs/prompts/README.md`](README.md) for L0 / L1 / L2 layering and safety notes (spec 026).

This document previously described an Edge Function / Gemini-era prompt that
instructed the model to **generate** crisis counseling. That policy is retired:
crisis turns route to a **static resource card** (`CrisisResourceCard`) with
zero model generation (spec 019 R7 / spec 026).
