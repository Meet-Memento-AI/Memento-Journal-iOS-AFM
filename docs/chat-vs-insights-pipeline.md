# Chat vs batch Insights (pipelines)

> **Superseded.** Shipping Ask vs Weekly/Patterns is specs 017 / 019 / 037 /
> 039 (on-device). This page describes the deleted Gemini Edge Functions.

## Chat (`supabase/functions/chat`)

- **Per message**: embeds an **effective query** (condensed recent turns + current user text), runs **pgvector** `match_journal_entries` (top-K, thresholded), injects context into Gemini.
- **Citations**: the model returns `cited_entry_ids`; the API exposes only those entries as `sources` (with excerpts), not the full retrieval set.
- **Not** a full journal scan: similarity search over embedded rows only.

## Insights (`supabase/functions/generate-insights`)

- **Batch analysis** for periodic insights (e.g. monthly): sends up to **`MAX_ENTRIES` (20)** journal entries to the model, each truncated (`MAX_CONTENT_LENGTH` per entry).
- **Different** from chat RAG: broader text window for synthesis, not per-message retrieval.

Users should understand chat as **query-driven memory** with citations when the reply is grounded in specific entries; insights as **summarized windows** over many entries at once.
