# Thousand-prompt sweep — what Memento says to ordinary questions

**Measured 2026-08-23**, iOS 27 simulator, on-device Foundation model, through the real
`FoundationModelsIntelligenceService.askStream` path, against the 262-entry persona corpus
in `Fixtures/corpus`.

Companion to [`POWER_USER_CHAT_SIMULATION.md`](POWER_USER_CHAT_SIMULATION.md). That one asks
*is the answer right* over 100 scored generations. This one asks a wider question — *what does
the app actually say when someone uses it like a journal* — over 1,000.

Reproduce:

```
# the sweep itself: ~100 min on one simulator, resumable, ~6s/generation
TEST_RUNNER_SWEEP=1 \
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -scheme MeetMemento \
  -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
  -parallel-testing-enabled NO -test-timeouts-enabled NO \
  -only-testing:MeetMementoTests/MementoPromptSweep

# the routing dump: no model, no simulator capability, milliseconds
xcodebuild test … -only-testing:MeetMementoTests/PromptSweepRouting
```

Shard across simulators with `TEST_RUNNER_SWEEP_SHARD` / `TEST_RUNNER_SWEEP_SHARDS`; output
lands in `.eval-runs/sweep/` (git-ignored), one JSONL row per generation, resumable by index.

---

## 1. What was run

`PromptSweepCorpus` generates 1,000 deterministic prompts across 20 shapes — the questions
people actually type into a journal, not benchmark questions:

| shape | n | shape | n |
|---|---|---|---|
| Summarize / recap | 85 | Decisions | 35 |
| Reflection | 85 | Small talk | 35 |
| Mood & feeling | 85 | Not-in-journal bait | 35 |
| People | 85 | Compare & synthesize | 35 |
| Time & recall | 85 | Follow-up turns | 35 |
| Habits & health | 65 | Search-shaped | 30 |
| What is Memento | 60 | Give me a prompt | 25 |
| Work | 55 | Typos & fragments | 25 |
| Venting | 45 | Low mood | 20 |
| Goals & follow-through | 40 | Gratitude & wins | 35 |

Prompts are interleaved by shape, so a partial run still samples all 20. Every prompt is
generated from a seeded RNG — prompt #417 is the same question on every machine, which is what
makes a killed run resumable.

Scoring reuses `ChatEvalScoring` verbatim. Nothing here gates: a flag means *read this one*.

## 2. Results

| | |
|---|---|
| generations | 1,000 |
| clean (no mechanical flag) | 869 |
| quoted a real entry | 69% |
| median reply | 88 words / 487 chars |
| median latency, one simulator | **5.7s** (p90 7.3s) |
| median latency, four in parallel | 23.2s (p90 29.9s) |
| hard guardrail refusals | 10 |

The run used four simulators at once, which quadrupled throughput and also quadrupled latency;
**56 generations crossed the app's own 30s watchdog** under that load and were regenerated
serially. Treat 5.7s as the product number and 23.2s as a contention artefact.

## 3. Findings

1. **The voice collapses into one register.** 752 replies use *quiet*, 469 use *rhythm*, 419 use
   both, 354 reach for *the weight of*. A pricing question, a greeting and a grief question all
   arrive in the same hush.
2. **Memento cannot describe itself.** 43 of 60 product questions were answered out of the
   journal — including *"Are my entries private?"*, which reaches into the journal to answer
   whether the journal is private.
3. **Summarize is the most common ask and the thinnest answer.** 43 of 85 recaps cited nothing;
   median 329 chars against 498 for the run.
4. **`###` leaks into prose** in 255 replies, mid-paragraph in 229 of them.
5. **Follow-ups start over.** 26 of 35 turns carrying history retrieved fresh entries instead of
   reusing the grounding of the turn they referred to.
6. **Bait usually gets answered.** Of 35 prompts naming things absent from the journal, 4 said so;
   27 cited a real entry anyway.
7. **The guardrail refuses grief.** 4 of the 10 hard refusals name grief, in a journal whose
   most-cited entry is the morning the user's grandmother died.
8. **Small talk and low mood are handled well.** 33 of 35 greetings under 220 chars with no
   retrieval; all 20 low-mood turns warm and uncited. One crack: an empty name slot renders
   *"Hey,,"*.

## 4. Root cause: one classifier, three misroutes

`PromptSweepRouting` classifies all 1,000 prompts with no model and joins the result to the
generations. The finding is unambiguous:

> **0 of 1,000 replies quoted an entry on a channel not permitted to retrieve.**

`RetrievalPolicy` and `ReplyChannel.allowsRetrieval` hold perfectly. Every wrong citation is a
`TurnClassifier` decision made before retrieval ever ran:

| symptom | classification | should be |
|---|---|---|
| product questions answered from the journal | 44 of 60 → `journalQuery` | `meta` (6 of 1,000 turns ever reached it) |
| recaps thin and uncited | 23 imperatives → `share` → `companion` (no retrieval, 128-token cap); 23/23 cited nothing | `journalQuery` |
| follow-ups re-retrieve | 26 of 35 → `journalQuery` | `followup` → `thread` |

Channel distribution over the run: `notebook` 723, `companion` 207, `redirect` 36, `phatic` 13,
`continuer` 10, `meta` 6, `thread` 5.

## 5. Next steps

**P0 — `TurnClassifier`.** One component behind three symptoms.

- A second-person subject (*you*, *this app*, *Memento*) with no first-person journal reference
  must not resolve to `.journalQuery`. Downstream policy already correct; no change needed there.
- Recap verb coverage: *condense*, *sum up*, *walk me through*, *write a short summary of*,
  *give me a recap/breakdown of*. *Summarize* and *catch me up on* already route correctly, so
  this is a vocabulary gap, not a design one.
- Short anaphoric turns with history should prefer `.followup` and let
  `RetrievalPolicy.followupMode` decide whether to reuse the previous grounding.
- Turn `PromptSweepRouting`'s dump into assertions — expected turn type per category. It needs
  no model and runs in milliseconds, so it belongs on the merge lane.

**P1**

- Strip a mid-paragraph `###` in the decode path, alongside the existing reference-marker
  stripping.
- Land `QueryDateWindow` — time questions cited nothing 29% of the time and five recaps denied
  having entries for a month the corpus covers.
- Add a stock-phrase frequency check to `ChatEvalScoring` so register collapse is a tracked
  number, then loosen the register in the `ask@` recipe.

**P2**

- Drive the no-match reply from `RetrievalPolicy.isGrounded` / `EntryRetriever` confidence rather
  than leaving "is this a miss" to the generation.
- Decide the product answer for a single guardrail refusal on a subject the journal is full of.
  `RefusalOutageTracker` already separates a *run* of refusals from one decision.
- Empty name slot should drop its comma.

---

Full browsable transcript of all 1,000 replies, with per-card routing, citations and flags:
<https://claude.ai/code/artifact/2b4e08c7-2110-4afd-897b-8b226093ba66>
