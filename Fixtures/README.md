# Fixtures — Evaluation Corpus (spec 013 R4)

Synthetic journal corpus for retrieval/reflection evaluation. Referenced by:
spec 013 (Spike A), spec 016 (recall@5 CI gate, `REQ-IDX-010`), spec 022
(Evaluations-framework gates), spec 017 (guardrail refusal-rate measurement).

**Never ship this in the app bundle.** Test/eval targets only.

## Layout

```
Fixtures/
├── README.md            ← this file: schema + persona + narrative arcs
├── corpus/
│   └── entries-YYYY-MM.json   (9 files, 2025-11 … 2026-07, ~262 entries)
├── gold/
│   ├── questions.json   ← ≥40 retrieval queries with known-correct entry IDs
│   └── adversarial.json ← persona-adherence prompts (never answered with advice)
└── validate_corpus.py   ← structural validation (counts, IDs, classes, dates)
```

## Entry schema

```json
{
  "id": "e-2026-03-08-1",          // e-YYYY-MM-DD-n, unique, stable
  "createdAt": "2026-03-08T21:40:00Z",
  "source": "voice",               // voice | text  (~70/30 split)
  "transcript": "…",               // the journal text, first person, speakable register
  "seedMoods": ["anxious"],        // ground-truth labels for eval, ≤3, from the fixed vocabulary
  "seedTopics": ["family"],        // ≤4, fixed vocabulary
  "placeName": "home",             // coarse or null
  "weatherSummary": "overcast",    // short string or null
  "class": "anchor"                // ordinary | anchor | heavy | sparse-week
}
```

Vocabularies (mirror the app's fixed enums, spec 016 `REQ-IDX-008`):
- moods: `anxious, calm, frustrated, hopeful, tired, energized, lonely,
  connected, grieving, content, restless, focused`
- topics: `work, family, relationships, health, running, sleep, creativity,
  home, money, grief, friends, weather`

Classes:
- **ordinary** — mundane day; the majority. Restraint gate: observation must be
  suppressed on ≥60% of these (spec 022 Gate 4).
- **anchor** — carries a fact a gold question retrieves. IDs are load-bearing:
  `gold/questions.json` references them. Do not renumber.
- **heavy** — grief/illness/conflict/self-critical content, for guardrail
  refusal-rate measurement (`technology/01` §11). Written with care, no
  gratuitousness.
- **sparse-week** — one of the deliberately thin weeks (see arcs), for
  `hasNothingToSay` testing.

## Persona

"J" — 33, product designer, mid-size tech company, Pacific-Northwest city.
Voice-journals mostly evenings and commutes; types when in meetings or bed.
Register: conversational spoken English, contractions, occasional trailing
thoughts. Entry length 40–120 words typical; anchors 120–260.

## Narrative arcs (anchor timeline)

1. **Work / burnout**: new manager Priya (Nov); "Atlas" project crunch (Dec);
   first says "burnt out" **2026-01-12** (`e-2026-01-12-1`); boundary attempts
   (Feb); considers quitting **2026-03-20**; tells Priya + moves to team
   "Meridian" **2026-04-14**; enjoys work again (Jun).
2. **Brother — Dario**: FIRST mention **2026-03-08** (`e-2026-03-08-1`, phone
   call after two years of distance). Coffee, awkward **2026-04-05**; helps him
   move **2026-05-17**; birthday dinner, genuine laugh **2026-06-21**; argument
   about their mother, recovers **2026-07-04**. *No entry before 2026-03-08 may
   mention a brother* — the honesty gold question depends on it.
3. **Running**: restart couch-to-5k (Nov); first 10k **2026-01-25**; knee-pain
   scare + physio (Mar); half-marathon 2:07 **2026-05-24**; running framed as
   mood regulation throughout.
4. **Sleep**: bad-sleep clusters Dec + Feb (correlating with work crunch);
   blackout curtains **2026-03-02**; improvement noted Apr.
5. **Grief — Nonna Lucia** (heavy class): declining health (Dec); dies
   **2026-02-09** (`e-2026-02-09-1`); funeral **2026-02-13**; grief waves Mar
   and Mother's Day **2026-05-10**.
6. **Apartment**: lease trouble (Apr); hunting (May); moves to Fremont
   **2026-06-14**; settling (Jul).
7. **Pottery**: Thursday class starts **2026-01-08**; first decent bowl
   **2026-02-26**; sells two pieces at a street market **2026-06-28**.
8. **Sam** (relationship): first date **2025-12-12**; good stretch Jan–Mar;
   breakup **2026-04-26** (`e-2026-04-26-1`); processing May; okay by Jul.
9. **Overcast-Monday motif**: on overcast Mondays (esp. Nov–Feb) mood reads
   flat/low; `weatherSummary: "overcast"` + a flat register. ≥6 instances —
   the correlation gold question counts them.
10. **Sparse weeks**: **2025-12-22 … 12-28** (exactly 2 short mundane entries)
    and **2026-05-04 … 05-10** (exactly 2, one being the Mother's Day grief
    entry's quiet aftermath on 05-10 — keep that one heavy, the other mundane).

## Counts

| Month | Entries | Notes |
|---|---|---|
| 2025-11 | 26 | arcs 1,3,9 start |
| 2025-12 | 24 | sparse week 12-22; Sam begins; Nonna declines |
| 2026-01 | 30 | burnout named; pottery + 10k |
| 2026-02 | 28 | Nonna dies (heavy cluster); bad sleep |
| 2026-03 | 30 | Dario first mention; knee; curtains |
| 2026-04 | 30 | team change; breakup |
| 2026-05 | 28 | sparse week 05-04; half-marathon; Dario move |
| 2026-06 | 32 | apartment move; birthday dinner; market |
| 2026-07 | 34 | through 07-22; argument + recovery |
| **Total** | **262** | ≥250 required, 9 months ≥ 8 required |

Gold questions live in `gold/questions.json` and reference anchor IDs — when
editing corpus text, never change an anchor's `id`, date, or its
question-relevant facts without updating the gold set and re-running
`validate_corpus.py`.
