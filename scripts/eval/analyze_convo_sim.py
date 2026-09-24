#!/usr/bin/env python3
"""Spec 048 R2/R6 — report over a `ConversationSimulation` run.

The 2026-09-20 study's published figures (046 findings 1 and 3, 047 findings 1
and 2) were counted by hand and nobody else can check them. This recomputes
them from the JSONL, so a second run's numbers arrive on the same footing as
the first one's.

    scripts/eval/analyze_convo_sim.py .eval-runs/convo-sim/<label>.jsonl
    scripts/eval/analyze_convo_sim.py --check-046 <the 2026-09-20 archive>

`--check-046` asserts the archive still yields the four numbers the spec
quotes. Run it before trusting anything this script says about a newer run;
if it fails, the discrepancy is the finding.

One definition matters and is reused everywhere. A **generated turn** is an
assistant row that the model actually wrote: not an `error` row (no
generation happened) and not a `statistic` row (`insight-fact@1`, which spec
037 rule 3 computes in Swift). Every rate below is over generated turns,
which is what 046 did.
"""
from __future__ import annotations

import argparse
import collections
import json
import statistics
import sys
from pathlib import Path

# Codes that mean the reply presented journal material the corpus does not
# support. Note `rule.boldNotTheirWords`, not `hall.` — it sits in the rule
# family despite being a grounding claim, and a set that guesses the prefix
# silently counts zero.
FABRICATION_CODES = (
    "hall.fabricatedQuote", "hall.uncitedQuote", "hall.firstPersonPerception",
    "hall.narrativeJoin", "rule.boldNotTheirWords",
)

# Every `TurnType` and `ReplyChannel` case, so 048 R2's "report the zero rows"
# means the cases the code actually has, not the ones a run happened to reach.
# Kept in sync by hand with Routing/TurnClassifier.swift and
# Routing/ReplyChannel.swift; `--check-enums` fails when a run produces a value
# missing from these, which is the drift that matters.
TURN_TYPES = (
    "social", "acknowledgement", "meta", "share", "followup", "journalQuery",
    "quantitative", "reflectiveQuestion", "offdomain", "correction",
)
REPLY_CHANNELS = (
    "phatic", "continuer", "meta", "companion", "thread", "notebook",
    "statistic", "redirect",
)

# `ChatEvalScoring.gating` excludes these three alongside `gen.*`: they are
# measured but do not gate until 046 R1's two warehoused runs have happened.
REPORT_ONLY_CODES = (
    "hall.fabricatedQuote", "hall.firstPersonPerception", "hall.narrativeJoin",
    # Added with the scorer in spec 051. `ChatEvalScoring.reportOnlyCodes` has
    # carried four entries since then; this tuple had three, so a turn whose
    # only fault was an unbacked date counted as gated here and did not in
    # Swift. Kept in sync by hand, which is why the mismatch lasted.
    "hall.unbackedDate",
)


def load(path: Path) -> list[dict]:
    rows = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as error:
            # A run killed mid-write leaves a torn final line. That is the
            # checkpointing working, not corruption, so say so and carry on.
            print(f"  ! {path.name}:{number} is not valid JSON ({error}); skipped",
                  file=sys.stderr)
    return rows


def generated(rows: list[dict], arm: str | None = None) -> list[dict]:
    return [
        row for row in rows
        if row.get("role") == "assistant"
        and not row.get("error")
        and row.get("prompt_version") != "insight-fact@1"
        and (arm is None or row.get("arm") == arm)
    ]


def pct(part: int, whole: int) -> str:
    return "—" if not whole else f"{100 * part / whole:.1f}%"


def violated(row: dict, *, include_report_only: bool = False) -> bool:
    """Did this turn break a rule that actually gates?

    `gen.*` is shape telemetry and the three `REPORT_ONLY_CODES` are measured
    but unarmed, so neither counts by default — mirroring
    `ChatEvalScoring.gating`. `include_report_only` exists because 046's
    published companion figure counted `gen.hitTokenCap`, and reproducing a
    number means reproducing how it was taken.
    """
    for violation in row.get("violations", []):
        code = violation["code"]
        if not include_report_only and (code.startswith("gen.") or code in REPORT_ONLY_CODES):
            continue
        return True
    return False


def table(title: str, rows: list[tuple]) -> None:
    print(f"\n### {title}\n")
    if not rows:
        print("_none_")
        return
    widths = [max(len(str(r[i])) for r in rows) for i in range(len(rows[0]))]
    for index, row in enumerate(rows):
        print("| " + " | ".join(str(cell).ljust(widths[i]) for i, cell in enumerate(row)) + " |")
        if index == 0:
            print("|" + "|".join("-" * (w + 2) for w in widths) + "|")


def report(path: Path) -> None:
    rows = load(path)
    manifest = path.with_suffix(".manifest.json")
    print(f"\n# {path.name}\n")
    if manifest.exists():
        data = json.loads(manifest.read_text())
        for key in ("started_at", "finished_at", "git_sha", "git_branch", "os_version",
                    "runs_per_arm", "min_messages", "max_messages", "history_message_limit"):
            if key in data:
                print(f"- **{key}**: `{data[key]}`")
        for arm in data.get("arms", []):
            span = arm.get("entry_date_range") or []
            window = f", {span[0][:10]} → {span[1][:10]}" if len(span) == 2 else ""
            print(f"- **arm `{arm['name']}`**: {arm['entry_count']} entries{window}")
        if "notes" in data:
            print(f"- **notes**: {data['notes']}")

    assistant = [r for r in rows if r.get("role") == "assistant"]
    errors = [r for r in assistant if r.get("error")]
    stats = [r for r in assistant if r.get("prompt_version") == "insight-fact@1"]
    gen = generated(rows)
    arms = sorted({r.get("arm") for r in assistant})
    print(f"\n{len(rows)} messages · {len(assistant)} assistant · {len(errors)} error "
          f"· {len(stats)} Swift-computed · **{len(gen)} generated**")

    # --- Per-arm headline
    head = [("arm", "generated", "gating violation", "invented material", "notebook", "cited")]
    for arm in arms:
        g = generated(rows, arm)
        head.append((
            arm, len(g),
            f"{sum(violated(r) for r in g)} ({pct(sum(violated(r) for r in g), len(g))})",
            (lambda n: f"{n} ({pct(n, len(g))})")(
                sum(any(v["code"] in FABRICATION_CODES for v in r.get("violations", [])) for r in g)),
            (lambda n: f"{n} ({pct(n, len(g))})")(sum(r.get("channel") == "notebook" for r in g)),
            (lambda n: f"{n} ({pct(n, len(g))})")(sum(bool(r.get("citations")) for r in g)),
        ))
    table("Headline, by arm", head)

    # --- Violation codes
    codes = [("code", *arms, "total")]
    counter = {arm: collections.Counter(v["code"] for r in generated(rows, arm)
                                        for v in r.get("violations", [])) for arm in arms}
    every = sorted({c for arm in arms for c in counter[arm]})
    for code in every:
        per = [counter[arm][code] for arm in arms]
        codes.append((code, *per, sum(per)))
    table("Violations by code (occurrences, generated turns only)", codes)

    # --- Rate per arm × channel: 046's 38.3% vs 6.8% comparison
    grid = [("arm", "channel", "generated", "gating violation", "invented material")]
    for arm in arms:
        g = generated(rows, arm)
        for channel, _ in collections.Counter(r.get("channel") for r in g).most_common():
            cell = [r for r in g if r.get("channel") == channel]
            inv = sum(any(v["code"] in FABRICATION_CODES for v in r.get("violations", [])) for r in cell)
            grid.append((arm, channel, len(cell),
                         f"{sum(violated(r) for r in cell)} ({pct(sum(violated(r) for r in cell), len(cell))})",
                         f"{inv} ({pct(inv, len(cell))})"))
    table("Violation rate by arm × channel", grid)

    # --- 048 R2: the confusion matrix, zero rows included
    # 048 R2: every case gets a row, including the ones at zero — a turn type
    # that stops firing has to be a visible result and not a missing row. Any
    # value the run produced that these tuples do not know about is appended
    # and flagged, because the alternative is silently dropping it.
    seen_turns = {r.get("turn_type") for r in assistant if r.get("turn_type")}
    seen_channels = {r.get("channel") for r in assistant if r.get("channel")}
    turn_types = list(TURN_TYPES) + sorted(seen_turns - set(TURN_TYPES))
    channels = list(REPLY_CHANNELS) + sorted(seen_channels - set(REPLY_CHANNELS))
    unknown = (seen_turns - set(TURN_TYPES)) | (seen_channels - set(REPLY_CHANNELS))
    matrix = [("turn_type", *channels, "total", "rate")]
    for turn in turn_types:
        cells = [sum(1 for r in assistant if r.get("turn_type") == turn and r.get("channel") == c)
                 for c in channels]
        label = turn if turn in seen_turns else f"{turn} (never fired)"
        if turn not in TURN_TYPES:
            label = f"{turn} (NOT IN TURN_TYPES — update the script)"
        matrix.append((label, *cells, sum(cells), pct(sum(cells), len(assistant))))
    table("TurnType × ReplyChannel (all assistant turns)", matrix)
    if unknown:
        print(f"\n! values this script does not know about: {sorted(unknown)} — "
              "add them to TURN_TYPES / REPLY_CHANNELS")

    for field, name in (("question_shape", "QuestionShape"), ("response_policy", "ResponsePolicy"),
                        ("evidence_state", "EvidenceState"), ("zone", "TrustZone")):
        present = [r for r in assistant if field in r]
        if not present:
            print(f"\n### {name}\n\n_not recorded in this run_")
            continue
        rowset = [(field, *arms, "total")]
        per_arm = {arm: collections.Counter(r[field] for r in present if r.get("arm") == arm)
                   for arm in arms}
        for value in sorted({v for arm in arms for v in per_arm[arm]}):
            counts = [per_arm[arm][value] for arm in arms]
            rowset.append((value, *counts, sum(counts)))
        table(name, rowset)

    # --- Citations, which only mean something where a corpus exists
    cite = [("arm", "turns with a citation", "citations", "mean per cited turn", "median entry age (days)")]
    for arm in arms:
        g = generated(rows, arm)
        cited = [r for r in g if r.get("citations")]
        total = sum(len(r["citations"]) for r in cited)
        ages = [c["entry_age_days"] for r in cited for c in r["citations"] if "entry_age_days" in c]
        cite.append((arm, f"{len(cited)} ({pct(len(cited), len(g))})", total,
                     f"{total / len(cited):.2f}" if cited else "—",
                     f"{statistics.median(ages):.0f}" if ages else "not recorded"))
    table("Citations", cite)

    # --- Latency
    lat = [("arm", "n", "p50", "p90", "max", "model p50", "degraded", "tools called")]
    for arm in arms:
        g = generated(rows, arm)
        secs = sorted(r["seconds"] for r in g if "seconds" in r)
        model = sorted(r["model_seconds"] for r in g if "model_seconds" in r)
        if not secs:
            continue
        p = lambda xs, q: xs[min(len(xs) - 1, int(q * len(xs)))]
        lat.append((arm, len(secs), f"{statistics.median(secs):.2f}s", f"{p(secs, 0.9):.2f}s",
                    f"{max(secs):.2f}s",
                    f"{statistics.median(model):.2f}s" if model else "—",
                    sum(bool(r.get("was_degraded")) for r in g),
                    sum(r.get("tools_called", 0) for r in g)))
    table("Latency and generation state", lat)

    # --- The history window: the reason the run is 20–50 messages and not 10
    win = [("arm", "before window closes", "gating rate", "after window closes", "gating rate")]
    for arm in arms:
        g = generated(rows, arm)
        before = [r for r in g if not r.get("history_truncated")]
        after = [r for r in g if r.get("history_truncated")]
        win.append((arm, len(before), pct(sum(violated(r) for r in before), len(before)),
                    len(after), pct(sum(violated(r) for r in after), len(after))))
    table("Before vs after the history window closes", win)

    # --- Spec 050: what the model emitted, as against what shipped
    packed_any = [r for r in gen if r.get("evidence_pack")]
    if packed_any:
        rows_ = [("arm", "with a pack", "pack matched", "pointed (quote)", "pointed (date)",
                  "needed cleanup", "chips")]
        for arm in arms:
            packed = [r for r in generated(rows, arm) if r.get("evidence_pack")]
            if not packed:
                continue
            matched = [r for r in packed if r["evidence_pack"].get("state") == "matched"]
            q = sum(1 for r in packed if r["evidence_pack"].get("expanded_quotes"))
            d = sum(1 for r in packed if r["evidence_pack"].get("expanded_dates"))
            dirty = sum(1 for r in packed
                        if (r["evidence_pack"].get("adopted_quotes", 0)
                            + r["evidence_pack"].get("stripped_italics", 0)
                            + r["evidence_pack"].get("dropped_quotations", 0)) > 0)
            rows_.append((arm, len(packed), f"{len(matched)} ({pct(len(matched), len(packed))})",
                          f"{q} ({pct(q, len(matched))} of matched)",
                          f"{d} ({pct(d, len(matched))} of matched)",
                          f"{dirty} ({pct(dirty, len(packed))})",
                          sum(r.get("chips", 0) for r in packed)))
        table("Spec 050 — did the model point, or did the renderer clean up?", rows_)

        counters = [("counter", *arms, "reads as")]
        meaning = {
            "adopted_quotes": "model wrote pack text verbatim but unmarked",
            "stripped_italics": "model still reached for italics",
            "dropped_quotations": "model quoted something nothing backs — sentence dropped",
            "dropped_markers": "marker resolved to nothing",
            "duplicate_quotes": "same quote twice",
            "unwrapped_bold": "bold not backed by the pack",
            "stripped_dates": "raw date in glue prose — 050 R3 bans these",
            "dropped_headings": "heading the renderer could not back",
            "slots": "evidence slots offered to the model",
        }
        for key, note in meaning.items():
            per = [sum(r["evidence_pack"].get(key, 0)
                       for r in generated(rows, arm) if r.get("evidence_pack")) for arm in arms]
            counters.append((key, *per, note))
        table("Renderer counters (occurrences)", counters)

    # --- Conversation shape, and the harness's own artefacts
    shape = [("arm", "conversations", "reached planned length", "median achieved",
              "fallback person turns", "person generation errors", "designed refusals")]
    for arm in arms:
        runs = collections.defaultdict(list)
        for r in rows:
            if r.get("arm") == arm:
                runs[r["run_id"]].append(r)
        reached = sum(1 for turns in runs.values()
                      if len(turns) >= turns[0].get("planned_messages", 0))
        achieved = sorted(len(t) for t in runs.values())
        shape.append((
            arm, len(runs), f"{reached} ({pct(reached, len(runs))})",
            statistics.median(achieved) if achieved else "—",
            sum(1 for r in rows if r.get("arm") == arm and r.get("move") == "fallback"),
            sum(1 for r in rows if r.get("arm") == arm and r.get("generation_errors")),
            sum(1 for r in rows if r.get("arm") == arm and r.get("designed_refusal")),
        ))
    table("Conversation shape (and harness artefacts, which are not app findings)", shape)

    # --- Persona and intent, split by arm rather than pooled.
    #
    # Pooling hides the thing worth knowing. On the 2026-09-20 archive
    # p06-planner pools to 29.6% and looks like the worst persona in the cast;
    # split, that is 39.5% with no journal against 18.5% with one — a persona
    # the archive *helps* more than any other. And pooling cannot show sign at
    # all: three personas come out worse with a journal than without, which is
    # a different kind of finding from "this persona scores badly".
    for field, name in (("persona_id", "Persona"), ("intent_id", "Opening intent")):
        rowset = [(field, *[f"{arm} rate" for arm in arms], "delta", "worse with a journal?")]
        baseline = "empty" if "empty" in arms else arms[0]
        for value in sorted({r.get(field) for r in gen if r.get(field)}):
            cells, rates = [], {}
            for arm in arms:
                cell = [r for r in generated(rows, arm) if r.get(field) == value]
                hits = sum(violated(r) for r in cell)
                rates[arm] = 100 * hits / len(cell) if cell else None
                cells.append(f"{hits}/{len(cell)} ({pct(hits, len(cell))})")
            seeded = [a for a in arms if a != baseline]
            if len(arms) == 2 and rates[baseline] is not None and rates[seeded[0]] is not None:
                delta = rates[seeded[0]] - rates[baseline]
                rowset.append((value, *cells, f"{delta:+.1f}pp", "yes" if delta > 0 else ""))
            else:
                rowset.append((value, *cells, "—", ""))
        table(name, rowset)


def check_046(path: Path) -> int:
    """Assert the archive still yields what specs 046 and 047 quote."""
    rows = load(path)
    assistant = [r for r in rows if r.get("role") == "assistant"]
    gen = generated(rows)
    empty = generated(rows, "empty")
    notebook = [r for r in empty if r.get("channel") == "notebook"]
    companion = [r for r in empty if r.get("channel") == "companion"]
    followup = sum(1 for r in assistant if r.get("turn_type") == "followup")

    claims = [
        ("generated assistant turns", len(gen), 3119),
        ("zero-entry generated turns", len(empty), 1597),
        ("zero-entry turns in notebook voice", len(notebook), 588),
        ("TurnType.followup over all assistant turns", followup, 5),
    ]
    # 046 quotes 38.3% and 6.8%. Only the second needs `gen.*` counted in to
    # land — no `gen.*` code ever fired on notebook — so the published pair
    # compares a gating-only rate against a rate that includes report-only
    # shape. Corrected, the contrast is 38.3% vs 5.6%: wider, not narrower.
    rates = [
        ("notebook/empty violation rate",
         sum(violated(r, include_report_only=True) for r in notebook), len(notebook), 38.3),
        ("companion/empty violation rate (as published, gen.* counted)",
         sum(violated(r, include_report_only=True) for r in companion), len(companion), 6.8),
    ]

    bad = 0
    print(f"\n# --check-046 against {path.name}\n")
    for label, got, want in claims:
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  {label}: {got} (spec says {want})")
    for label, part, whole, want in rates:
        got = 100 * part / whole if whole else 0
        ok = abs(got - want) < 0.1
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  {label}: {got:.1f}% of {whole} (spec says {want}%)")
    # Two published figures are *not* checkable here, and saying so is the
    # point: a check that quietly omits them reads as fuller than it is.
    print()
    print("not checkable from this archive:")
    print("  046's \"212 zero-entry turns present invented journal material\" is a REPLAY "
          "figure.\n    The archive was scored with the broken regex, so "
          f"hall.fabricatedQuote appears {sum(1 for r in rows for v in r.get('violations', []) if v['code'] == 'hall.fabricatedQuote')} "
          "times in it.\n    Reproducing 212 means re-running the Swift scorer over the "
          "archived bodies, not reading\n    the recorded violations.")
    print(f"  the archive's own grounding codes: "
          + ", ".join(f"{code}={sum(1 for r in rows for v in r.get('violations', []) if v['code'] == code)}"
                      for code in FABRICATION_CODES))
    print("\n" + ("every checkable published figure reproduces" if not bad
                  else f"{bad} figure(s) do not reproduce — that is the finding, not a script bug to paper over"))
    return 1 if bad else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("jsonl", nargs="+", type=Path)
    parser.add_argument("--check-046", action="store_true",
                        help="verify the archive reproduces specs 046/047's published figures")
    args = parser.parse_args()
    if args.check_046:
        return max(check_046(p) for p in args.jsonl)
    for path in args.jsonl:
        report(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
