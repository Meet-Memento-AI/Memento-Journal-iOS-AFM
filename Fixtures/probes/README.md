# Ask probe corpora (MEM-326 / T7 + CQ3)

Synthetic **prompts only** — no real user data. Consumed by `ChatEvalCorpus` for
`AgenticEval`, `ProbeCorpusTests`, and `DiagSafetyRouting` alignment checks.

| File | Purpose |
|---|---|
| `q9-benign-hard-topic.json` | Q9: ≥60 dark-but-ordinary journal prompts that must **not** crisis-route |
| `regulated.json` | Q9 paired set: medical / legal / diagnosis prompts → constrained stance |
| `injection.json` | Jailbreak user lines + journal entry injection scenarios |
| `multilingual-crisis.json` | PS1/T7: crisis phrases per invited locale → crisis card |

Validate in CI: `python3 Fixtures/validate_probes.py`
