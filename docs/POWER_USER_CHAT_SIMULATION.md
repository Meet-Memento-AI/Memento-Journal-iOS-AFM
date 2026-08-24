# Power-user chat simulation — 100 generations against a 262-entry journal

**Measured 2026-08-23**, iOS 27 simulator (`ChatDiag27`), on-device Foundation model,
through the real `FoundationModelsIntelligenceService.askStream` path.

Reproduce:

```
TEST_RUNNER_CHAT_EVAL=1 \
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -scheme MeetMemento \
  -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
  -parallel-testing-enabled NO \
  -only-testing:MeetMementoTests/ChatEvalGate

# retrieval-only, no model, seconds instead of minutes:
TEST_RUNNER_RETRIEVAL_DIAG=1 xcodebuild test … \
  -only-testing:MeetMementoTests/RetrievalRecallDiag
```

---

## 1. What was simulated

A power-user persona: **262 entries, November 2025 → July 2026**, roughly one a day —
work (Atlas, then Meridian), a grandmother's illness and death, a breakup, a
brother reappearing after two years, pottery classes, a running habit, a move.

**100 generations across 17 scenario types**, in two halves:

| half | n | corpus | what it measures |
|---|---|---|---|
| gold set | 45 | 262 entries | is the answer **right** — do the citations point at the entries that actually answer the question |
| conversational | 55 (11 shapes × 5) | attribution corpus | is the reply **well-formed** — no leaked scaffolding, no fabricated quotes, correct attribution, one closing question |

Gold categories: *temporal*, *event*, *person*, *pattern*, *synthesis*, and
*honesty* — three questions the journal deliberately cannot answer, to see
whether the app admits it or invents a source.

Scoring is mechanical throughout. No judge model, no human read: every check is
true or false about the text.

---

## 2. Where it broke

The conversational half was healthy. The recall half was not.

- **51/55 conversational** — casual, meta, follow-ups, bait and share turns all
  behaved.
- **19/45 gold** — and **22 of the 26 failures were grounding failures**: the
  reply cited the wrong entry, cited nothing, or cited something on a question
  nothing supports.
- **0/3 honesty traps.** Every question the journal cannot answer came back with
  citations. One reply said *"I can't recall the exact timing of that winter
  outing, but the entries don't hold a clear trace"* — and displayed **three
  citations** underneath it.

That last shape is the most damaging thing a journal app can do: it attaches the
person's own words to a claim those words do not support, and the citation UI
makes it look verified.

---

## 3. Root cause

The failures came from **one layer**, and it was not the model.

`EntryRetriever` ranks on three signals — semantic cosine, keyword overlap,
recency. The keyword term had three defects that compound on a large corpus.

### R1 · Keyword matching had no word boundaries

`text.contains(term)` matched inside words. `go` hit *going* and *ago*; `back`
hit *background*; `into` hit almost every entry.

Simulated over the 262-entry corpus with the old scorer:

| question | expected entry's keyword rank | top-scoring entry scored on |
|---|---|---|
| "When did I get back into running?" | **115** (score 0.0) | *get / back / into* noise |
| "What was I working on last December?" | **73** (score 0.0) | *last* |
| "When did I switch teams at work?" | **57** | *work* |
| "When did the crunch on Atlas start?" | **37** | *start* |
| "When did I go skiing last winter?" — *unanswerable* | — | scored **5.0** on *go / last*, produced 3 citations |

### R2 · No term rarity

Every term counted the same, so *first*, *thing*, *actually* and *work* outvoted
*Nonna*, *Atlas*, *pottery* and *skiing*. On a 262-entry corpus that is the
difference between a term in 82 entries and a term in 2.

### R3 · Dates were invisible

An entry's `createdAt` participated in ranking only through a recency decay. A
question naming a month, season or year had no way to reach the entries written
then, because the date is metadata and almost never appears in the text:

- "What did I hear about Nonna's health **in December**?" → cited February and April 2026
- "What was I working on **last December**?" → cited July 2026
- "Tell me about the fight with Dario **in July**." → cited nothing
- "What did I write about my brother **in 2025**?" → cited a March **2026** entry, on a question whose correct answer is *nothing*

### R4 · The signal bar was also deciding the shortlist

`hasSignal` (cosine ≥ μ+σ, or keyword ≥ 2.0) decided *whether* the turn was
grounded — and then the entries that failed it were discarded outright. Over 262
entries only a handful clear μ+σ, so a question whose answer sat just under the
bar lost that entry completely while the prompt went out with fewer entries than
it had room for.

---

## 4. The fix

Four changes, all inside retrieval. No prompt changes, no model changes.

| layer | change | file |
|---|---|---|
| matching | word-boundary matching with a short inflection allowance (`class`↔`classes`, `die`↔`died`), never inside a word | `EntryRetriever.containsWord` |
| weighting | IDF over the live corpus, normalised so ~5% document frequency weighs exactly 1.0 — the old flat weight — and clamped to `[0.15, 2.0]`; flat below 30 entries where the statistics are noise | `EntryRetriever.termWeight` |
| dates | a date grammar resolving "in December", "last winter", "this spring", "in 2025", "the last year" to a range, applied as a **hard constraint** on candidates | `QueryDateWindow.swift` (new) |
| shortlist | the bar decides whether the turn is grounded; the ranking fills the remaining prompt slots. Plus two honesty rules: inside a named range the words must land too, and a question whose content words appear **nowhere** in the journal cannot be grounded | `EntryRetriever.retrieve` |

The two honesty rules are what close the traps. "What did I write about my
brother in 2025?" now returns **empty** — the corpus has no 2025 entry that
mentions him — so the stance is `.noMatch` and `reconcileCitations` has nothing
to cite. Same for "When did I go skiing last winter?".

The stopword list also grew, for a reason IDF cannot cover: this author writes
*going*, *getting* and *happened* far more often than the bare stems, so `go`,
`get` and `happen` looked *rare* to IDF while contributing nothing but noise.
`first`/`last`/`start` are safe to drop there because origin and recency are
detected from the raw question by `seeksOrigin`, not from the keyword terms.


---

## 5. What changed at the retrieval layer

Measured by `RetrievalRecallDiag`, which reproduces the query `prepareAsk` builds
for a journal question and asks a question the chat gate cannot: **was the
expected entry ever in the prompt at all?** That separates a retrieval miss (the
entry never reached the model — no prompt work can fix it) from a selection miss
(it was there and the model cited a neighbour).

| metric | value |
|---|---|
| recall@5 — an expected entry reached the prompt | **33/42** |
| recall@20 — an expected entry reached the candidate pool | 38/42 |
| full recall@5 — *every* expected entry reached the prompt | 28/42 |
| turns falling through to ambient background | 1/45 |
| honesty traps that still return entries | **1/3** |

Every date-constrained question now lands its expected entry at rank 0–3:

| question | expected entry's rank |
|---|---|
| "What did I hear about Nonna's health in December?" | 0 |
| "Tell me about the fight with Dario in July." | 0 |
| "What was Mother's Day like this year?" | 0 |
| "How was coffee with my brother in April?" | 1 |
| "What happened with my knee in March?" | 2 |
| "How often did I write about running this spring?" | 0, 2, 3 |

Two of the three honesty traps now return **nothing**, so the prompt goes out
with `entries=0` and there is no citation to invent.

---

## 5c. End-to-end re-run — and why its headline is not usable

The same 100 generations were re-run with the fix in place. **The headline
number from that run should not be quoted**, and it is worth being explicit
about why.

While it ran, five other simulator test suites were running on the same machine
(a second agent session, which had already killed one attempt at generation 53
by relaunching the app on a shared simulator). Median generation time went from
**6s to 26s**, and **13 of 100 generations died on the 30-second stream-idle
watchdog** — a failure mode that did not occur once in the baseline.

| run condition | median generation | watchdog timeouts | completed |
|---|---|---|---|
| baseline, quiet machine | 6s | 0 | 98/100 |
| verification, 6 concurrent suites | 26s | **13** | 85/100 |

Raw totals: 70/100 → 61/100. That drop is 13 timeouts and normal run-to-run
variance, not a regression — but it also means the run cannot be used to claim
an improvement.

### What survives the caveat

| measure | before | after |
|---|---|---|
| wrong-citation violations | 15 | **8** |
| over-citation on unanswerable questions | 3 | **1** |
| grounding faults per completed recall question | 0.51 | **0.39** |
| recall questions passing, of those that completed | 19/43 | **19/33** |
| honesty traps answered honestly | 0/3 | **2/3** |

Timeouts are not randomly distributed — they favour long generations — so the
completed-only rates are indicative, not clean.

The conversational half read 51/55 → 42/52 completed. That is **not** attributable
to the change: `rule.boldNotTheirWords` scored 6, then 0, then 5 across three runs
of the *identical* prompt, so this gate's conversational half has a run-to-run
spread of roughly ±5, and retrieval does not touch bolding.

### The traps, in the model's own words

Both closed traps now answer with **zero citations**:

> **"What did I write about my brother in 2025?"**
> I don't see anything from the entries about your brother in 2025; the stretch
> doesn't appear in the records. What is it you're searching for now?
>
> — 0 citations. Was: a March **2026** entry, cited 3 times.

> **"When did I go skiing last winter?"**
> I don't see anything from that stretch, not a trace of when you went skiing
> last winter.
>
> — 0 citations. Was: the same honest wording, with 3 citations under it.

The third behaves exactly as predicted and stays open: asked about "my dog", the
reply reaches for *dogs and strollers and other runners nodding as we passed* on
the canal path. Retrieval found a real mention of a real dog.

### One unplanned win

The date grammar fired on a conversational turn it was not written for. "What did
I write on July 4th?", asked of a corpus whose entries are all from August, now
resolves to a July window, finds it empty, and hands the model nothing to quote.

### What this does not establish

A headline pass rate. That needs one more run on a quiet machine, and it is the
one number this report deliberately does not claim.

---

## 6. What is still wrong

### The remaining misses are near-misses

Before the fix, expected entries sat at ranks 115, 73, 57 and 37, or were
discarded entirely. They now cluster at ranks 5, 5 and 6 — **one slot outside
the prompt window**. That is ranking nuance, not blindness.

| prompt cap | questions whose answer reaches the model |
|---|---|
| 5 (today) | 33/42 |
| 6 | 35/42 |
| 7 | 36/42 |
| 20 (candidate pool) | 38/42 |

Spec 037 R7 pins the Ask block at 3–5 entries. **Raising it to 7 is the single
highest-leverage lever left** — worth three more gold questions — but it is a
product decision about prompt width and latency, not a bug fix, so it was left
alone here.

### Two things retrieval cannot fix

- **Vocabulary gaps.** "How did my first 10k go?" cannot be matched lexically:
  the journal writes *ten k*. Only the embedding can bridge that, and here it
  does not.
- **Possessive judgement.** "What have I said about my dog?" is a trap — the
  person has no dog. The journal does mention *a couple of people walking a dog*
  and *dogs and strollers* on the canal path. Retrieval finds them correctly;
  deciding neither is *my* dog is a judgement about meaning and belongs to the
  reply, not the ranking. This is the one trap still leaking.

### Style violations are small-model non-compliance

A handful of replies still open with "You wrote" or land two question marks.
`PromptRegistry.ask` bans both explicitly, in as many words. That is the small
on-device model failing to comply, not a missing rule — adding more prompt text
without a measurement behind it is a guess.

---

## 7. Instruments

| instrument | answers | cost |
|---|---|---|
| `ChatEvalGate` | is the reply right and well-formed, end to end? | 100 live generations, ~15 min |
| `RetrievalRecallDiag` *(new)* | did the answer ever reach the model? | no model, seconds |

`RetrievalRecallDiag` is the addition that made this tractable. The chat gate can
say *"cited e-2026-01-15-1, expected e-2026-01-08-1"* but not whether the
expected entry was ever in the prompt — and those are two different defects with
two different fixes. Retrieval is deterministic given (query, entries), so the
diagnostic reproduces the query `prepareAsk` builds and reports the rank of every
expected entry. Both suites are skipped by default and write Markdown plus JSON
to `.eval-runs/`.

### A note on running these

Four attempts at a clean 100-generation verification run failed, each on a
different environmental fault and none in the code:

1. **Shared simulator.** A second agent session started its own
   `xcodebuild test-without-building` on the same device, relaunching the app
   under the running test — died at generation 53.
2. **Machine load.** Six concurrent simulator suites took median generation
   time from 6s to 26s; 13 generations died on the 30-second stream-idle
   watchdog.
3. **Wedged device.** `Simulator device failed to launch … No such process`
   after 27 generations.
4. **`simctl erase`.** It un-wedges the device — and takes the on-device model
   assets with it, after which `availability()` is no longer `.available` and
   the gate skips instead of running.

The lesson for whoever runs these next: a long eval needs its own simulator and
a quiet machine, isolated DerivedData is not sufficient, and erasing the device
is not a recovery step. This is a good argument for running the gate in CI on a
dedicated runner rather than locally.

