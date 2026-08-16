# Ask GenUI — implementation map

Companion to [spec 028](../028-ask-markdown-and-genui.md) (dialect) and
[028-ask-genui-ideation.md](028-ask-genui-ideation.md) (sketches). Still
not Swift. This file answers: **when** a part is emitted, **which** primitive
wins, **what** AFM is asked to do, and **how** we know it worked.

The load-bearing choice: **Swift selects the asset. AFM writes the sentences.**
That is how the existing Ask path already works for stance
(`TurnClassifier` → `RetrievalPolicy` → prompt tag). GenUI is the same
pattern one layer down. The on-device model is not asked to pick among eight
widgets, fill nested optionals, or do arithmetic. Those are the jobs it is
worst at, and they are the jobs that waste context.

---

## 1. What AFM is good at here

On-device Foundation Models (and later PCC) earn their keep on Ask when we
use the APIs that constrain them, and skip the ones that make them guess.

| AFM capability | Use on Ask GenUI | Do not use for |
|---|---|---|
| `@Generable` + `@Guide` | `AskAnswer` stays small: heading, markdown body, `citedRefs` | A union of eight optional part structs (schema tokens crowd out journal evidence; the 3B model skips or duplicates nested fields) |
| Snapshot streaming | Typewriter the body. The GenUI block is known at retrieval time — emit it on the first delta, same as today’s `reviewedCitations` | Waiting for the model to “finish the chart” |
| Constrained `citedRefs` | Reconcile against the retrieved set | Letting the model invent ids or inline `[ref N]` |
| Tools / `CustomStage` (iOS 27, M6) | Count, group, score **in the retrieval loop** | Asking the model to approximate “how many” over prose |
| `GenerationOptions` | Lookup turns: lower temperature (draft **0.3**). Casual/share: keep **0.7** | One temperature for every stance |
| `tokenCount` / `contextSize` | If the List/Quote is on screen, **do not also dump those full excerpts into the prompt** — pass dates + ids + one-line stubs | Stuffing the window “in case” the model wants to recount |
| Skip `respond` entirely | `showMe` follow-ups and some `nothingFound` turns: template copy + payload, no generation | Forcing a model call so the bubble “feels AI” |
| `Evaluations` | `GenUIGate` on the fixture corpus (below) | Thumbs-up as the only quality signal |

Simple use cases are the product: *when, how many, which, is it in there.*
Those should be fast, exact, and mostly Swift. AFM’s job is a short caption
that does not contradict the number.

---

## 2. Pipeline (where the decision lives)

Insert one policy step next to the stance decision that already exists.
Do not add a second model call to “choose a layout.”

```
SafetyRouter                         → crisis / refuse / continue
TurnClassifier                       → social | share | journalQuery | followup | …
RetrievalPolicy + EntryRetriever     → entries, ambient?, empty?
LookupIntentClassifier  (new)        → none | count | last | first | list | …
GenUIPolicy             (new)        → primitive + payload | none
AskAnswer (AFM, optional)            → heading + markdown, given bound facts
ChatMessageBubble                    → chrome + 0..1 block
```

`LookupIntentClassifier` is precision-biased, like `TurnClassifier`: short
lexicons for *how many / when last / when first / what have I written / show
me / this month / weekends / keep coming back / what did I say / have I
written about X*. Ambiguous journal questions fall through to **`none`**
(prose + citation link only). A misfire that hides a widget is acceptable; a
misfire that shows a fake count is not.

`GenUIPolicy` is a pure function of `(intent, retrieval, n, window)` →
`(primitive, payload)` or `none`. Tests should cover it without AFM.

**Send a GenUI asset only when all of these are true:**

1. Safety action is `continue` or `continueConstrained` (never on crisis / refuse).
2. Turn is `journalQuery` or a `followup` whose anchor was a lookup
   (never social, acknowledgement, meta, offdomain, share).
3. Retrieval is **topical**, not ambient (`isAmbient == false`). Ambient
   background must not become a Measure.
4. Intent is not `none`.
5. The payload’s n clears the primitive’s **show** threshold (table below).
6. At most one primitive. If two could apply, the **specificity ladder**
   wins (Quote > Measure > List > Span > Pair > Rank).

Follow-up “show me” / “what else” / “those” reuses `followupAnchor` and
forces intent `showMe` → List, **skipping AFM** when the previous payload
is still in memory.

---

## 3. Thresholds (draft)

Design can move the numbers; the *shape* is the contract: every comparison
or rank has a floor, every list has a cap, every zero is a Window.

| Primitive | Show when | Cap / collapse | Never |
|---|---|---|---|
| **Window** | topical ask, `n == 0` | — | On casual/share; on ambient retrieval |
| **Quote** | last / first / “what did I say”, `n ≥ 1` | 1 excerpt, ≤ ~280 chars, verbatim | Paraphrase; two quotes unless intent is `contrastTwo` |
| **Measure** | `howMany`, `n ≥ 1` | One number, noun, `k of corpus · window` | A second number that implies a trend |
| **List** | `inventory` / `month` / `showMe`, `n ≥ 2` | **5** rows; overflow → “N of M · show all ›” | `n == 1` (collapse to Quote); `n == 0` (Window) |
| **Span** | `first` with `n ≥ 2`, or `notSince` with a last date | — | `n == 1` (Quote) |
| **Pair** | contrast ask, **each side ≥ 5** | Same unit, same window | Either side `< 5` → Note + optional List |
| **Rank** | `recurring`, **total ≥ 8** and top item ≥ 3 | **3** rows, closed vocab only | Free-form tags; `total < 8` → List |
| **Cadence** | `howOften`, **≥ 4** matches (3 intervals) | Median + the raw gaps | `n < 4` → Span or List |
| **Month strip** | `whichMonths`, **≥ 3** months in the window with any data | Label every month including `0` | `< 3` months of journal history → List |
| **Note** | any comparison/rank that failed its floor | One line | Warning icon, shame copy |
| **Chart** (M5) | Patterns’ `REQ-SUR-001` floor (do not fork) | Same view as Patterns | Chat-only chart design |

**Corpus floor.** If the whole journal has **&lt; 3** entries, never Pair /
Rank / Cadence / strip. Point at writing a first entry (already the empty
journal copy in `AIChatView`).

**Exactness.** Displayed numbers are Swift’s. If AFM’s caption contains a
numeral that disagrees, the caption loses (strip or regenerate once; do not
show both). Coexistence rule from 028, made mechanical.

---

## 4. Specificity ladder (one block)

When a question matches more than one intent, pick the **most particular
artifact**, not the flashiest.

```
nothingFound     → Window
whatDidISay      → Quote
last / first     → Quote (n=1) or Span (n≥2, first+last only)
howMany          → Measure
showMe           → List (no prose, no AFM)
inventory / month / photos → List
notSince         → Span
weekdayWeekend / beforeAfter / lengthPair → Pair or Note
recurring / together → Rank or List
howOften         → Cadence or Span
whichMonths      → strip or List
contrastTwo      → two Quotes
else             → none (citation link only)
```

“Has how I talk about the job changed?” is `contrastTwo`, not Rank. We do
not name “change.”

---

## 5. Use-case map

Columns:

- **Objective** — why the block exists (user job).
- **AFM role** — what the model is allowed to do.
- **Send if** — conditions on top of §2.
- **Design** — primitive + collapse.
- **Success** — how we know.

Gold categories in parentheses map to `Fixtures/gold/questions.resolved.json`.

### Simple path (ship first — most of the gold set)

These four primitives cover temporal, person, event, and honesty questions.
They should feel instant: the block can paint **before** the first token.

#### A. Nothing there (honesty)

| | |
|---|---|
| **Use case** | “What did I say about climbing?” / gold honesty q-16–18 |
| **Objective** | Trust. The journal is the only world. Absence is an answer. |
| **AFM** | Optional. Prefer a **template** (“I don’t find anything about {query}.”) + Window. If AFM writes, bind `matched: 0` and forbid invention. |
| **Send if** | `journalQuery`, topical retrieval empty or `n == 0` after filters |
| **Design** | Window. No List of “related.” No heading. |
| **Success** | **100%** of honesty gold questions render Window and **0** citations; `RetrievalGate` still requires search (or today’s retriever to have run); 0 world-knowledge sentences (Persona/Grounding sample). User: does not try the same miss twice in a session because they believe the miss. |

#### B. The last / first time (temporal)

| | |
|---|---|
| **Use case** | “When did I last write about Dario?” / gold temporal |
| **Objective** | Put them back in a day they already lived. |
| **AFM** | One or two sentences. Bind `date` + `excerpt`. Must not invent a second date. |
| **Send if** | intent last/first, `n ≥ 1`, not ambient |
| **Design** | Quote (`n == 1`) or Span (`first` and `n ≥ 2`). Excerpt verbatim. |
| **Success** | Quote date **equals** `min`/`max` `createdAt` of the gold expected IDs **100%**. Excerpt is a substring of that entry. Caption contains no other calendar date. p50: block visible with first delta. |

#### C. How many (count)

| | |
|---|---|
| **Use case** | “How many times did I write about work this year?” |
| **Objective** | A number they can trust, not a vibe. |
| **AFM** | Caption only. Bind `count`, `corpus`, `window`. Temperature 0.3. No numerals except those bound (lint). |
| **Send if** | intent `howMany`, `n ≥ 1` |
| **Design** | Measure. Tap → citations sheet / List. |
| **Success** | Displayed integer **==** Swift count **100%** on a fixture with known `derive` counts. Caption contradiction rate **0%**. Thumbs-up rate on count turns ≥ prose-only journal turns (directional, study). |

#### D. What’s in there / a month / show me (inventory)

| | |
|---|---|
| **Use case** | “What have I written about sleep?” · “What did I write in March?” · follow-up “show me” |
| **Objective** | See their own sentences, not our summary of them. |
| **AFM** | Inventory: short intro, **do not** restate the list. **showMe: skip AFM.** |
| **Send if** | intent inventory/month/showMe, `n ≥ 2` (`n == 1` → Quote) |
| **Design** | List, max 5, “N of M · show all ›”. Rows are Buttons → entry. |
| **Success** | Row ids ⊆ retrieval ids **100%**. Order = recency (newest first) unless they asked a month (oldest first). showMe: **no** model call; latency ≈ persistence read. Overflow never renders a 6th row. |

#### E. What did I actually say (quote)

| | |
|---|---|
| **Use case** | “What did I say about leaving?” |
| **Objective** | Their wording is the artifact. |
| **AFM** | One sentence around the Quote. Must not rephrase the excerpt in the caption. |
| **Send if** | intent `whatDidISay`, `n ≥ 1` |
| **Design** | Quote only. Do not add Measure `1`. |
| **Success** | Excerpt byte-substring of the entry. Caption paraphrase-of-excerpt rate, sampled, ≤ 5%. |

### Contrast and pattern (second wave — easy to lie)

Only after A–E are green. These are where AFM and GenUI most often fight.

#### F. Weekdays / before-after / length

| | |
|---|---|
| **Use case** | “Do I write more on weekends?” · “After I moved…” (date they named) |
| **Objective** | Two honest piles, same unit. |
| **AFM** | May say “more on weekdays” **only if** the Pair is shown (both sides ≥ 5). If Note, AFM must not claim a comparison. |
| **Send if** | contrast intent, parseable split (weekday, or a date in the question) |
| **Design** | Pair, or Note + List. |
| **Success** | Pair shown iff both sides ≥ 5, **≥ 95%** on fixtures. When Note, caption contains no “more/less/often.” Split date is the one they typed, not an inferred “the move.” |

#### G. Recurring / together / which months

| | |
|---|---|
| **Use case** | “What do I keep coming back to?” · “Work and sleep together?” |
| **Objective** | Frequency in a **closed** vocabulary, or three intersection counts. |
| **AFM** | Names only labels that appear in the Rank. No extra themes. |
| **Send if** | Rank floors in §3; else collapse to List |
| **Design** | Rank (3 rows) or three-number block for intersection; month strip labels zeros. |
| **Success** | Labels ⊆ ThemeCatalog / seedTopics **100%**. Collapse rate on sparse fixtures ≥ 90% (Restraint cousin). Intersection `both + onlyA + onlyB` == union. |

#### H. Cadence / not since / quiet month

| | |
|---|---|
| **Use case** | “How often do I write about sleep?” · “Have I written about her lately?” · “Did I write in May?” |
| **Objective** | Spacing or absence as a **record**, never a prod. |
| **AFM** | Forbidden copy: should, streak, fallen off, you haven’t written. Lint these. |
| **Send if** | cadence n ≥ 4; notSince has a last match; quiet month `n == 0` in that month |
| **Design** | Cadence / Span / Window+neighbours |
| **Success** | PersonaGate extras: 0 shame phrases on these intents. Quiet month does not fire unless they asked about that month. |

#### I. Two moments (no “growth”)

| | |
|---|---|
| **Use case** | “Has how I talk about the job changed?” |
| **Objective** | Let them read two days. We do not name the arc. |
| **AFM** | No “you’ve grown / gotten worse / used to.” Two Quotes, maybe a heading. |
| **Send if** | `n ≥ 2` topical matches spanning ≥ 30 days (draft) |
| **Design** | two Quotes (earliest and latest in set) |
| **Success** | Caption contains no valence/change lexicon (list in tests). Dates are min and max of the set. |

#### J. Photos / length / time-of-day

| | |
|---|---|
| **Use case** | “Which entries have photos?” · “Are my entries getting shorter?” |
| **Objective** | Properties of **stored fields**, labelled honestly (`hasPhoto`, word count, **time saved**). |
| **AFM** | Length/time captions must repeat the field name (“median words”, “time saved”). |
| **Send if** | photos: `hasPhoto` count ≥ 1 → List; length: both windows ≥ 5 else Note |
| **Design** | List without thumbnails; Pair of medians |
| **Success** | Photo rows all `hasPhoto == true`. Time-of-day **not shipped** until a copy review signs “time saved” (easy to misread as when they felt it). |

#### K. Later — mood / place (M5+)

| | |
|---|---|
| **Use case** | Mood mix, home vs away |
| **Objective** | Same numbers Patterns already computes. Chat inlines; it does not re-guess from prose. |
| **AFM** | Reads the bound Rank. Must not add untagged moods. |
| **Send if** | Field exists on entries; Patterns floor; user opted into place |
| **Design** | Rank, or Patterns chart once `REQ-SUR-001` is real |
| **Success** | Chat n **equals** Patterns n for the same window. Missing place ≠ “home.” |

---

## 6. AFM call shapes (optimize the simple path)

Three call kinds. Default to the cheapest that is still true.

| Kind | When | Session | Output |
|---|---|---|---|
| **0. No generate** | `showMe`; some `nothingFound` | — | Template + payload |
| **1. Caption** | last/first/howMany/quote/inventory | `AskAnswer`, temp 0.3, facts bound, **no full excerpt dump** if Quote/List is on screen | heading + short markdown |
| **2. Conversation** | share, reflective, grounded-but-intent-none | today’s temp 0.7, evidence block as now | heading + body, citation link, **no** extra primitive |

Kind 0 is the simple-use-case win: “show me those” is a list they already
earned. Paying cold-model latency to re-greet them is how AFM is wasted.

Kind 1 prompt stub (illustrative):

```
[Facts — do not contradict]
count: 14
window: 2026-01-01 .. 2026-08-16
corpus: 61
noun: entries about work
dates_on_screen: [2026-08-02, 2026-07-11, 2026-06-03]   // if List
[Turn: journal question]
```

Kind 1 does **not** include a `@Generable` `parts` field. The part is
already chosen. That keeps the schema at three fields, which AFM already
streams reliably (`heading1` → `heading2` → `body`).

M6 (Spotlight + stages) changes **who computes** count/group, not who
**selects** the primitive. Policy stays in Swift. The stage output becomes
the payload.

---

## 7. Design rules at implementation time

Unchanged chrome: `Reviewed your journals ›` if topical retrieval ran;
action bar after stream; crisis card still a presentation switch.

- Paint the GenUI block on the **first delta** (payload is ready). Do not
  wait for the typewriter. Use the same insertion transition as citations
  so the body is not shoved twice.
- One block. No nested cards. `theme` / `type` tokens only — not the old
  purple Insights language.
- List rows are `Button`s (ScrollView tap-to-dismiss).
- Speak: sanitizer on markdown; Measure/Window get a one-line caption;
  List/Rank skipped or “N entries, from March to August.”
- `showMe` and Window templates are authored copy, versioned next to
  `PromptRegistry`, not model output — so PersonaGate can grep them.

---

## 8. Metrics

Layered like spec 022: automatable gates on fixtures, then a thin study
slice. Do not invent a sixth personality for the product.

### `GenUIGate` (fixture, CI-able once labelled)

Add `expectedPrimitive` + `expectedPayload` (count / entry ids / zero) to a
**subset** of gold questions — do not relabel synthesis/pattern as widgets.

| Metric | Threshold (draft) | Notes |
|---|---|---|
| Primitive exact match vs gold | ≥ 90% | Window/Quote/Measure/List only on v1 labels |
| Numeric exactness | **100%** | Displayed count == Swift count |
| Id exactness | **100%** | List/Quote ids ⊆ retrieved ∩ expected |
| Over-display | **0%** | social/share/meta gold-negatives must get `none` |
| Honesty | **100%** | q-16–18 → Window, 0 citations, 0 world knowledge |
| Collapse | ≥ 95% | Pair/Rank/Cadence not shown under floors |
| Caption contradiction | **0%** | numeral in body ≠ payload (lint) |
| Shame/advice on lookup templates | **0%** | PersonaGate wordlist |
| Kind-0 skip rate on `showMe` fixtures | **100%** | no `LanguageModelSession.respond` |
| Block-before-token | p50 ≤ retrieval time + 50ms | instrumentation, not a merge gate |

GroundingGate still owns citation accuracy ≥ 95%. GenUIGate owns **the
block matching the math**. A correct caption around a wrong number is a
fail.

### Product / study (spec 022 R5 slice, not a new study)

On lookup turns only (intent ≠ none):

| Signal | Why |
|---|---|
| Thumbs on turns **with** a block vs without, same intent family | Did the asset help |
| Regenerates on Measure/List turns | Often means the number felt wrong or the list felt random |
| Immediate follow-up “show me” after Measure | The Measure did its job |
| Repeat of an honesty question in-session | The miss was not believed |
| Time-to-first-block vs time-to-first-token | Swift is doing the work |
| Session continues after Window (they write, or they ask something else) | Absence didn’t feel like a broken bot |

Qualitative, 022’s “worth reading” analogue for Ask: *“It showed me something
I actually wrote, or a number I could check.”* Target: **≥ 80%** on lookup
turns in the study cohort, same spirit as weekly reflection’s bar — but
**fail closed** (hide the widget) rather than ship a pretty lie.

### AFM health (log, content-free — CONSTITUTION rule 3)

Per lookup turn: `intent`, `primitive`, `n`, `kind` (0/1/2),
`promptVersion`, `zone`, latency, `wasDegraded`. No query text, no excerpts.
Watch: Kind-1 latency vs Kind-2; Kind-0 fraction; collapse fraction (if it
is ~0%, floors are too low and we are over-drawing).

---

## 9. Build order (aligned with 028, optimized for simple cases)

Do not implement Rank/Pair/Chart before A–E are measurable.

| Step | Ship | AFM | Gate to leave |
|---|---|---|---|
| **G0** | `LookupIntentClassifier` + `GenUIPolicy` + thresholds as data | none | Unit tests, no model |
| **G1** | Window + Quote + Measure + List + showMe skip | Kind 0/1 | GenUIGate v1 on honesty/temporal/count/inventory labels |
| **G2** | Bind facts; stop double-dumping excerpts; temp 0.3 on lookups | Kind 1 cheaper | Context-budget log; contradiction lint |
| **G3** | Pair / Rank / Cadence / Note collapses | Kind 1 | Collapse ≥ 95%; Persona shame list |
| **G4** | contrastTwo, photos, length | Kind 1 | Field-honesty tests |
| **G5** | Charts / mood / place | Patterns numbers only | n parity with Patterns |
| **G6** | `CustomStage` payloads | Policy unchanged | 016 consumption test |

G1 is the user-facing whole product for simple Ask. Everything after is
restraint around comparisons.

---

## 10. What “optimized for AFM + simple use cases” means in one sentence

**Classify the lookup in Swift, count in Swift, paint one block immediately,
and ask the on-device model only for a short caption that cannot disagree —
or ask it for nothing at all.**
