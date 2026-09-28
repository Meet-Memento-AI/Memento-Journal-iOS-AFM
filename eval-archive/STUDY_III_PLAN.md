# Study III — plan

**Goal:** repeat Study II exactly, against the pipeline that landed spec 050, and
write the result up as a second paper measuring what changed.

**This is not a new idea.** Spec 050's front matter reads
`status: in-progress — implementation landed; Mac lane verification and the re-sim
are pending`, and R7 ("Eval hooks and the re-sim plan") already names the baselines
this run has to beat — they are Study II's numbers. Study III is 050's own pending
acceptance work.

---

## What changed between Study II and Study III

| | Study II (Sep 22, 01:51) | Study III |
|---|---|---|
| base | `main` @ `5fa700f` + 3 chat commits | `session1-scorer-repair` @ `a8d450d` |
| Ask prompt | `ask-core@17` | `ask-core@19` |
| quote vehicle | italics, by contract | `{{quote:N}}` / `{{date:N}}` markers |
| renderer | none — model's text shipped | `ReplyRenderer`, single choke point |
| arms | `empty` + `persona` | **same** |
| corpus | `Fixtures/corpus`, 262 entries | **same** |
| length | 20–50, seeded per run id | **same** |
| scorers | same eight | **same** |

Only the pipeline moves. Study II changed the world *and* the pipeline and was
confounded for it; Study III is the clean single-variable comparison — the first of
the three.

## The trap this study has to avoid

`hall.fabricatedQuote` fires on an italic span not found verbatim in the corpus.
Spec 050 R3 **retires italics entirely** (`ask-core@19`: "Never italics") and
`ReplyRenderer` strips unmarked italics before the body ships.

So the metric will fall whether or not the model improved. A drop is consistent with:

- **(a)** the model stopped inventing quotations, or
- **(b)** the vehicle was removed, so the detector has nothing left to detect.

Reporting the drop alone would repeat 046's original error in a new place — reading
an absence of violations as quality. The study therefore measures two different
things and never conflates them:

**Product level — what reached the screen.** The rendered body, scored by the same
eight scorers as Study II. This answers "would a user have seen a fabricated quote?"

**Model level — what the model emitted.** `ReplyRenderStats`, already captured by
050's R7 hook, records what the renderer had to clean up:

| field | reads as |
|---|---|
| `adoptedQuoteCount` | model wrote pack text verbatim without marking it |
| `strippedItalicCount` | model still reached for italics |
| `droppedQuotationCount` | model quoted something nothing backs — sentence removed |
| `droppedMarkerCount` | model emitted a marker that resolved to nothing |
| `expandedQuoteSlots` / `expandedDateSlots` | model pointed correctly |

This answers "did the 3B model learn to point, or is Swift cleaning up after it?" —
which is the question the last paper's thesis actually makes a claim about.

## Pre-registration

Written and committed **before** the run, so the result can falsify it. The last
paper argued reference failure is structural, not a prompting deficit; that predicts
the product improves sharply while model compliance stays partial.

| # | Prediction | Threshold | Source |
|---|---|---|---|
| P1 | Persona `hall.fabricatedQuote` falls sharply | from 56.0% (911/1,626) to **< 10%** of generated turns | 050 R7 "sharp drop" |
| P2 | Empty-arm gating does not regress | **≤ 6%** (was 5.5%) | 050 R7 explicit |
| P3 | Invented dates on the zero-entry arm fall | from 9 to **≤ 2** | 050 R3 bans absolute dates in glue |
| P4 | The model does **not** comply cleanly on its own | `adoptedQuoteCount + strippedItalicCount + droppedQuotationCount` > 0 on **≥ 25%** of seeded generated turns | the reference-failure thesis |
| P5 | Routing is unchanged | `followup` stays within ±10pp of 77.1%; `correction` stays at 0 | 050 lists `TurnClassifier` degeneracy as out of scope |
| P6 | Citation rate holds | seeded `cited` ≥ 35% (was 40.5%) | renderer must not suppress grounding |
| P7 | Latency rises but stays usable | seeded p50 ≤ 6.0s (was 4.50s) | rendering and pack building are added work |

P4 is the one that matters most for the thesis. If the model turns out to comply
cleanly — markers used correctly, nothing to strip — then the previous paper
overstated how structural the limit is, and that is the finding.

## Steps

1. **Branch** `study3-resim` from `a8d450d`. Do not touch the user's working branch.
2. **Port the harness** from `study2-persona-arm`: the `persona` arm in `buildArms`,
   and the widened row capture (`heading1`, `heading2`, `zone`, `model_seconds`,
   `body_chars`/`body_words`, `question_shape`, `response_policy`, `evidence_state`,
   citation dates, manifest build identity and arm date ranges). Keep 050's R7 fields
   — they are additive and this plan depends on them.
3. **Port the analysis**: `analyze_convo_sim.py`, `export_convo_sim_json.py`,
   `export_convo_sim_rows.py`, `build_comparison_page.py`, `eval-archive/` with both
   prior runs. Extend the analyzer and exporter with an `evidence_pack` section and
   the model-versus-product split above.
4. **Commit the pre-registration** as `eval-archive/STUDY_III_PREREGISTRATION.md`,
   before any generation.
5. **Verify**: `xcodebuild build-for-testing` under Xcode 27; then
   `ChatEvalScoringTests`, `ReplyRendererTests`, `EvidencePackBuilderTests`,
   `AskPromptContractTests`, `AskPromptSizeTests`; then
   `check_single_intelligence_importer.sh`.
6. **Pilot** 2 conversations per arm. Confirm markers are being emitted and expanded,
   `evidence_pack` is populated, and citations resolve to real fixture ids.
7. **Full run** 100 per arm on `ChatDiag27`, label `full-2026-09-23-resim`. Budget 5–7h
   (Study II took 4h50m; rendering and pack building add work).
8. **Archive** the JSONL and manifest into `eval-archive/convo-sim/`, regenerate
   aggregates and rows.
9. **Paper II** — `docs/CONVERSATION_SIMULATION_STUDY_III.md` plus a new artifact,
   structured as a replication with a pre-registered hypothesis: design, what changed,
   results against each prediction, the product-versus-model split, threats, and a
   verdict on whether the previous paper's thesis survived.

## Decisions taken, with reasons

- **Two arms, not three.** Re-running the 8-entry `cold` arm would complete the world
  × pipeline matrix but costs ~2h more and answers a question nobody asked. The
  `empty` and `persona` arms are what 050 R7 names.
- **Same seeds, same cast.** Run ids are unchanged, so conversation lengths replay
  identically and per-turn-index comparison against Study II is exact.
- **No raw-body capture.** Recording the model's pre-render text would mean changing
  `AskResult` in the app target to carry it. `ReplyRenderStats` already answers the
  model-level question in counts, so the app stays untouched. Recorded as a limitation.
- **Scorers unchanged.** Study III must be scored the way Study II was or the
  comparison dissolves. Where 050 changed a scorer's meaning, the paper says so rather
  than the analyzer silently compensating.

## Threats this study will carry

- **`hall.fabricatedQuote` is not the same measurement in both studies.** Its vehicle
  was retired between them. Reported as two numbers, never as one trend line.
- **Prompt version changed** (`@17` → `@19`), so any difference is attributable to the
  whole 050 change set, not to the renderer alone.
- **Single seeded world** still — one authored persona, as before.
- **Both interlocutors still synthetic.**
- **The person's side also changed.** `ask-core@19` affects only the assistant, but the
  person's turns are generated from the assistant's replies, so a changed assistant
  produces a changed conversation. Turn-for-turn comparison past turn 1 is not
  paired — only the distributions are comparable.
