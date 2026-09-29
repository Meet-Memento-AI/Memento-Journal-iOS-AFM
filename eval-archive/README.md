# eval-archive

Raw output from the long-form conversation studies, kept in the repo on purpose.

`.eval-runs/` is gitignored — it is scratch, regenerated on every run. That was
fine until specs 046 and 047 started quoting figures from a run that existed
only on one laptop. Nobody else could check them, and one of them turned out
not to be reproducible from the artifact at all (see **Caveats**). So the runs
that specs cite live here instead, unchanged, as the harness wrote them.

Everything here is synthetic. The journals are `Fixtures/`, the people are
persona briefs, both sides of every conversation were generated. No real
journal text has ever been in these files, which is what lets them be
committed at all (CONSTITUTION §4 rule 3).

## What is here

| Run | Messages | Arms | Produced by |
|---|---|---|---|
| `convo-sim/full-2026-09-20` | 6,984 | `empty` (0 entries), `cold` (8, `Fixtures/cold-start`) | branch `convo-sim-harness`, `e4d1621` + `ad59c95` |
| `convo-sim/full-2026-09-21-persona` | see manifest | `empty` (0 entries), `persona` (262, `Fixtures/corpus`, nine months) | branch `study2-persona-arm` |

The 2026-09-20 run is the one specs 046, 047 and 048 were written from. It is
described in several places as "100 conversations with entries and 100
without"; its manifest is the authority, and it says the seeded arm was the
**8-entry** cold-start journal. The nine-month corpus did not reach the
long-form harness until the 2026-09-21 run.

## Reading it

Newline-delimited JSON, one object per **message**, appended as each message is
produced (`ConversationSimulation.flush`) so a five-hour run survives being
killed. A torn final line means the run was interrupted, not that the file is
corrupt.

`<label>.manifest.json` is written twice — once when the run starts, once when
it finishes. `finished_at` present means the run completed; absent means it did
not, and the JSONL is a partial run that still counts.

### Every row

| Key | |
|---|---|
| `run_id` | `<label>/<arm>/<000>`. The harness seeds its RNG from an FNV-1a hash of this, so a conversation's planned length replays exactly |
| `arm` | `empty`, `cold` or `persona` — see the manifest for each arm's entry count and date range |
| `persona_id`, `intent_id` | the cast cell (`ConversationSimulationCast`); 10 × 10, walked with a coprime stride |
| `planned_messages` | sampled per run in `[min_messages, max_messages]`, always even |
| `turn_index`, `role`, `text`, `recorded_at` | |

### The person's rows (`role: "user"`)

| Key | |
|---|---|
| `move` | what this turn was told to do (push back, go quiet, change the subject…). `fallback` means the simulator's own guardrail refused to write the turn twice and a scripted line was used — a harness artefact, not an app finding |
| `generation_errors` | why the person's turn failed to generate, when it did |

### The assistant's rows (`role: "assistant"`)

Routing, recorded **before** generation, so a refused or timed-out turn still
says where the pipeline sent it:

`turn_type`, `channel`, `evidence_state`, `question_shape`, `response_policy`,
`history_messages`, `history_truncated`.

Generation, present only when a reply came back:

`prompt_version`, `model_identifier`, `zone`, `was_degraded`, `tools_called`,
`heading1`, `heading2`, `body_chars`, `body_words`, `seconds` (harness
wall-clock, includes stream overhead), `model_seconds` (`AskResult.latency`).

`citations[]`: `entry_uuid`, `fixture_id` (traceable back to
`Fixtures/corpus/*.json`), `excerpt`, `entry_created_at`, `entry_age_days`.

`facts[]`: Swift-computed `InsightFact` values (spec 045 R5). A row with
`prompt_version: insight-fact@1` is the Swift `statistic` path — the model did
not write it, so it is excluded from every rate.

`violations[]`: `{code, detail}` from the scorers the manifest's `scorers` key
names. On failure: `error`, `text_is_fallback`, `designed_refusal`. A
`designed_refusal` is the app working as specified (spec 026), recorded in
place with the bubble's own copy; the conversation continues.

## Analysing it

```
scripts/eval/analyze_convo_sim.py eval-archive/convo-sim/full-2026-09-21-persona.jsonl
scripts/eval/analyze_convo_sim.py --check-046 eval-archive/convo-sim/full-2026-09-20.jsonl
```

`--check-046` re-derives the figures specs 046 and 047 publish. Run it before
trusting the script on anything newer; if it fails, that is a finding.

## Caveats

**Fields arrive over time.** The 2026-09-20 run has no `heading1`/`heading2`,
`zone`, `model_seconds`, `question_shape`, `response_policy`, `evidence_state`,
`body_chars`/`body_words`, or citation dates — they were being computed and
discarded. Absent is not zero.

**A code absent from a run is ambiguous unless the manifest says otherwise.**
It can mean the scorer did not fire, or that it was not run. The `scorers` key
exists to disambiguate, and the 2026-09-20 manifest does not have it.

**`hall.fabricatedQuote` is 0 across the whole 2026-09-20 run, and that is the
bug, not the result.** Its regex could not compile, `spans()` swallowed the
throw with `try?`, and it returned empty for every input it was ever given
(fixed in `df3d59d`). 046's "212 zero-entry turns present invented journal
material" is a *replay* figure — the repaired scorer run back over these
bodies — and cannot be recomputed from the `violations` arrays in this file.

**046's 38.3%-vs-6.8% pair is not measured the same way on both sides.** 38.3%
is gating codes only; 6.8% needs `gen.hitTokenCap` counted in to land. No
`gen.*` code ever fired in notebook voice, which is why only the companion
number moves. Gating-only throughout, the contrast is 38.3% vs 5.6% — wider
than published, not narrower.
