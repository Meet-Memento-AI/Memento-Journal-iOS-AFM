# Study V — the endpoints the sweep sits between

Computed with `analyze_size_sweep.Cell` over the archived runs, so every number
here is taken by the same code that will read Study V. Generated turns only.

| study | arm | entries | sessions | turns | cited | gated | fabricated | unbacked dates | markers/turn | p50 s |
|---|---|---|---|---|---|---|---|---|---|---|
| I `full-2026-09-20` | cold | 8 | 100 | 1522 | 428 (28.1%) | 187 (12.3%) | 0 (0.0%) | 0 (0.0%) | 0.00 | — |
| I `full-2026-09-20` | empty | 0 | 100 | 1597 | 0 (0.0%) | 287 (18.0%) | 0 (0.0%) | 0 (0.0%) | 0.00 | — |
| II `full-2026-09-21-persona` | empty | 0 | 100 | 1760 | 0 (0.0%) | 97 (5.5%) | 1 (0.1%) | 0 (0.0%) | 0.00 | 1.70 |
| II `full-2026-09-21-persona` | persona | 262 | 100 | 1626 | 659 (40.5%) | 278 (17.1%) | 911 (56.0%) | 0 (0.0%) | 0.00 | 4.50 |
| III `full-2026-09-23-resim` | empty | 0 | 100 | 1667 | 0 (0.0%) | 107 (6.4%) | 0 (0.0%) | 0 (0.0%) | 0.00 | 1.64 |
| III `full-2026-09-23-resim` | persona | 262 | 100 | 1661 | 641 (38.6%) | 208 (12.5%) | 0 (0.0%) | 0 (0.0%) | 0.15 | 4.57 |
| IV `full-2026-09-24-spec051` | empty | 0 | 100 | 1669 | 0 (0.0%) | 77 (4.6%) | 0 (0.0%) | 13 (0.8%) | 0.00 | 1.83 |
| IV `full-2026-09-24-spec051` | persona | 262 | 100 | 1721 | 693 (40.3%) | 189 (11.0%) | 0 (0.0%) | 35 (2.0%) | 0.23 | 4.31 |

Study V runs the **Study IV pipeline**, so Study IV's two rows are its
endpoints: 0 entries and 262 entries, with the sweep covering 1–100 between them.

## P4 was mis-anchored, and this table says so before the result arrives

The pre-registration set P4 at "gated ≤ 6% in every size bin", citing the empty
arm's 5.5%. That was the wrong anchor and this table shows why: **no seeded arm
in four studies has ever gated below 11%.** Study IV's persona arm gates at
11.0%, Study II's at 17.1%, Study I's 8-entry cold arm at 12.3%. An empty
journal gates low because there is nothing to retrieve and most turns are
social; the moment a journal has entries, retrieval runs and the turns that
gate become possible at all.

So P4 is expected to fail, and its failure will say nothing about corpus size.
It is recorded here, before the numbers land, rather than being quietly
reinterpreted afterwards. The comparison P4 *should* have made is against a
seeded arm, which is the 11.0% in the last row.

## One prior data point bears directly on P2

Study I's `cold` arm is 8 entries and cites at **28.1%**; the 262-entry persona
arm cites at **40.5%**. If that gap is real and not an artefact of the pre-050
pipeline the cold arm ran under, citation rate *does* rise with corpus size and
P2's size-invariance prediction is already in trouble. Study V measures this
properly — same pipeline, 100 sizes — which is the point of running it.
