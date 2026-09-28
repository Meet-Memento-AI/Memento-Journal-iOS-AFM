# Chat RAG — product rules (testable)

> **Superseded.** Shipping Ask is on-device (`IntelligenceService`, specs
> 017 / 037 / 039). Retrieval skip for greetings and continuers is spec 039,
> not these Edge Function env vars. Kept as a historical record of the
> Gemini-era `chat` function.

These rules govern **journal retrieval** and **citations** in the `chat` Edge Function. They are implemented in [`supabase/functions/chat/`](../supabase/functions/chat/) (see env vars below).

## When to retrieve (embedding + `match_journal_entries`)

- Run retrieval when the **effective query** (recent turns + current message) is likely to benefit from journal grounding.
- **Skip** retrieval when:
  - The effective query is shorter than the configured minimum length, or
  - Heuristics classify the message as a pure acknowledgement or meta-chat (e.g. “thanks”, “ok”, “what can you do?”) — adjustable over time.

## When to show citations (`sources` in the JSON response)

- Return **`sources: []`** when:
  - Retrieval was skipped, or
  - The RPC returned no rows above threshold, or
  - The model returns **no** `cited_entry_ids`, or
  - Every cited ID is invalid (not in the context set) — invalid IDs are stripped server-side.

Citations are **answer-aligned**: only entry UUIDs the model lists in `cited_entry_ids` appear in `sources`, not every retrieved row.

## How many citations

- Default cap **3** (configurable via `CHAT_MAX_CITATIONS`). Never more than the number of entries in context for that turn.

## Tuning (environment)

| Variable | Role |
|----------|------|
| `CHAT_MATCH_COUNT` | RPC `match_count` (pool size). Default `5`. |
| `CHAT_MATCH_THRESHOLD` | Minimum similarity. Default `0.35`. |
| `CHAT_CONTEXT_MAX_ENTRIES` | Max entries passed into the context block after retrieval. Default `5`. |
| `CHAT_MAX_CITATIONS` | Max items in `sources`. Default `3`. |
| `CHAT_MIN_QUERY_LEN` | Minimum effective-query length to run retrieval. Default `10`. |
| `CHAT_EMBED_MAX_CHARS` | Max characters of `effectiveQuery` sent to the embedding model. Default `2000`. |

## Manual QA (release)

- Vague or meta message (“thanks”, “ok”) → retrieval skipped or weak matches; **`sources` empty or very small**.
- Specific question that clearly matches a dated entry → **1–2** intentional citations when the model grounds on those entries.
- Ask something unrelated to journal content → **`cited_entry_ids`** often `[]` and **`sources` empty**.
- After deploy, spot-check logs: `RAG:` line shows raw vs diversified counts when retrieval runs.

## Chat vs Insights

Chat uses **on-demand** vector retrieval + optional citations per message. **Monthly / batch insights** use a separate pipeline (`generate-insights`) with bounded entry batches and truncation — see [Chat vs batch insights](chat-vs-insights-pipeline.md).
