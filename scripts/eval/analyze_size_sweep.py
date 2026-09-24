#!/usr/bin/env python3
"""Study V — corpus-size sweep analysis.

Reads a `sweep` run's JSONL and reports behaviour as a function of journal
size, then scores each pre-registered prediction in
`eval-archive/STUDY_V_PREREGISTRATION.md`.

Deliberate choices, because they are the difference between a result and a
number:

*   **No per-size point is a result.** Two sessions per size is far too few.
    Per-size rows are printed for inspection and the verdicts are read off the
    bins, exactly as pre-registered.
*   **Every rate carries its numerator and denominator.** A bare percentage
    over 14 turns has misled this project before.
*   **Spearman is computed on the per-size series** (n as the unit, ~96
    points), not per-turn, so one chatty size cannot dominate.

Usage:
    python3 scripts/eval/analyze_size_sweep.py .eval-runs/<label>.jsonl
"""
from __future__ import annotations

import collections
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_convo_sim import (  # noqa: E402
    REPORT_ONLY_CODES,
    generated,
    load,
    pct,
    violated,
)

# Pre-registered in STUDY_V_PREREGISTRATION.md, before the run. Not adjusted
# to the data: a bin chosen after seeing the curve is not a bin, it is a claim.
BINS = ((1, 4), (5, 9), (10, 19), (20, 39), (40, 69), (70, 100))


def size_of(row: dict) -> int | None:
    """Journal size for a row, from the count written at capture time.

    Falls back to parsing the arm name so a run recorded before
    `arm_entry_count` existed can still be read.
    """
    count = row.get("arm_entry_count")
    if isinstance(count, int):
        return count
    arm = row.get("arm", "")
    if arm.startswith("size-"):
        try:
            return int(arm.split("-", 1)[1])
        except ValueError:
            return None
    return None


def spearman(xs: list[float], ys: list[float]) -> float | None:
    """Rank correlation, ties averaged. No scipy in this toolchain."""
    if len(xs) < 3 or len(xs) != len(ys):
        return None

    def ranks(values: list[float]) -> list[float]:
        order = sorted(range(len(values)), key=lambda i: values[i])
        out = [0.0] * len(values)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
                j += 1
            shared = (i + j) / 2 + 1
            for k in range(i, j + 1):
                out[order[k]] = shared
            i = j + 1
        return out

    rx, ry = ranks(xs), ranks(ys)
    mx, my = statistics.fmean(rx), statistics.fmean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    dx = sum((a - mx) ** 2 for a in rx)
    dy = sum((b - my) ** 2 for b in ry)
    if dx == 0 or dy == 0:
        return None
    return num / (dx * dy) ** 0.5


class Cell:
    """Everything measured at one journal size, or in one bin."""

    def __init__(self) -> None:
        self.turns = 0            # generated assistant turns
        self.cited = 0
        self.gated = 0
        self.fabricated = 0
        self.unbacked_dates = 0
        self.dropped_markers = 0
        self.slots_max: list[int] = []
        self.latencies: list[float] = []
        self.sessions: set[str] = set()
        self.states: collections.Counter = collections.Counter()
        self.codes: collections.Counter = collections.Counter()
        self.spans: list[str] = []

    def add(self, row: dict) -> None:
        self.turns += 1
        self.sessions.add(row.get("run_id", ""))
        if row.get("citations"):
            self.cited += 1
        if violated(row):
            self.gated += 1
        for violation in row.get("violations", []):
            code = violation["code"]
            self.codes[code] += 1
            if code == "hall.fabricatedQuote":
                self.fabricated += 1
            if code == "hall.unbackedDate":
                self.unbacked_dates += 1
        pack = row.get("evidence_pack") or {}
        if pack:
            self.dropped_markers += pack.get("dropped_markers", 0) or 0
            self.slots_max.append(pack.get("slots", 0) or 0)
            self.states[pack.get("state", "?")] += 1
        seconds = row.get("model_seconds")
        if isinstance(seconds, (int, float)):
            self.latencies.append(float(seconds))

    def merge(self, other: "Cell") -> None:
        self.turns += other.turns
        self.cited += other.cited
        self.gated += other.gated
        self.fabricated += other.fabricated
        self.unbacked_dates += other.unbacked_dates
        self.dropped_markers += other.dropped_markers
        self.slots_max += other.slots_max
        self.latencies += other.latencies
        self.sessions |= other.sessions
        self.states += other.states
        self.codes += other.codes
        self.spans += other.spans

    @property
    def p50(self) -> float | None:
        return statistics.median(self.latencies) if self.latencies else None

    @property
    def markers_per_turn(self) -> float | None:
        return self.dropped_markers / self.turns if self.turns else None


def verdict(ok: bool | None) -> str:
    if ok is None:
        return "UNTESTABLE"
    return "HELD" if ok else "FALSIFIED"


def report(path: Path) -> int:
    rows = load(path)
    turns = [r for r in generated(rows) if size_of(r) is not None]
    if not turns:
        print(f"no generated sweep turns in {path}", file=sys.stderr)
        return 1

    by_size: dict[int, Cell] = collections.defaultdict(Cell)
    for row in turns:
        by_size[size_of(row)].add(row)

    sizes = sorted(by_size)

    print(f"# Study V — corpus-size sweep\n\n`{path.name}`")
    print(f"\nsizes present: {len(sizes)} ({min(sizes)}–{max(sizes)}) · "
          f"generated turns: {len(turns)} · "
          f"sessions: {len({r.get('run_id') for r in turns})} · "
          f"all rows: {len(rows)}")

    # ---- per size (inspection only, never a result)
    print("\n## Per size — inspection only, two sessions each\n")
    print("| n | sessions | turns | cited | gated | phantom markers/turn | max slots | p50 s |")
    print("|---|---|---|---|---|---|---|---|")
    for n in sizes:
        c = by_size[n]
        p50 = f"{c.p50:.2f}" if c.p50 is not None else "—"
        mpt = f"{c.markers_per_turn:.2f}" if c.markers_per_turn is not None else "—"
        print(f"| {n} | {len(c.sessions)} | {c.turns} | "
              f"{c.cited} ({pct(c.cited, c.turns)}) | "
              f"{c.gated} ({pct(c.gated, c.turns)}) | "
              f"{mpt} | {max(c.slots_max) if c.slots_max else 0} | {p50} |")

    # ---- bins (where the verdicts are read)
    bins: dict[tuple[int, int], Cell] = {}
    for low, high in BINS:
        cell = Cell()
        for n in sizes:
            if low <= n <= high:
                cell.merge(by_size[n])
        bins[(low, high)] = cell

    print("\n## By size bin — pre-registered bins, where the trend is read\n")
    print("| bin | sizes | sessions | turns | cited | gated | fabricated quotes | "
          "unbacked dates | phantom markers/turn | p50 s |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for (low, high), c in bins.items():
        present = len([n for n in sizes if low <= n <= high])
        p50 = f"{c.p50:.2f}" if c.p50 is not None else "—"
        mpt = f"{c.markers_per_turn:.2f}" if c.markers_per_turn is not None else "—"
        print(f"| {low}–{high} | {present} | {len(c.sessions)} | {c.turns} | "
              f"{c.cited} ({pct(c.cited, c.turns)}) | "
              f"{c.gated} ({pct(c.gated, c.turns)}) | "
              f"{c.fabricated} ({pct(c.fabricated, c.turns)}) | "
              f"{c.unbacked_dates} ({pct(c.unbacked_dates, c.turns)}) | "
              f"{mpt} | {p50} |")

    # ---- evidence pack state by bin
    print("\n## Evidence-pack state by bin\n")
    states = sorted({s for c in bins.values() for s in c.states})
    print("| bin | " + " | ".join(states) + " |")
    print("|---" * (len(states) + 1) + "|")
    for (low, high), c in bins.items():
        total = sum(c.states.values())
        cells = [f"{c.states.get(s, 0)} ({pct(c.states.get(s, 0), total)})" for s in states]
        print(f"| {low}–{high} | " + " | ".join(cells) + " |")

    # ---- predictions
    print("\n## Pre-registered predictions\n")
    results: list[tuple[str, str, str]] = []

    small = Cell()
    for n in sizes:
        if n <= 4:
            small.merge(by_size[n])
    large = Cell()
    for n in sizes:
        if n >= 5:
            large.merge(by_size[n])

    # P1 — small-corpus cliff.
    #
    # Reported unconditionally. An earlier draft appended this only when both
    # sides had turns, so a partial run dropped the row entirely and the
    # summary still read "4/5 predictions held" — a prediction that cannot be
    # evaluated silently becoming one that was never made. Every prediction
    # below emits a row, UNTESTABLE included.
    if small.turns and large.turns:
        r_small = 100 * small.cited / small.turns
        r_large = 100 * large.cited / large.turns
        gap = r_large - r_small
        results.append((
            "P1 small-corpus cliff (>=10pp)",
            verdict(gap >= 10.0),
            f"n<=4 {small.cited}/{small.turns} = {r_small:.1f}% vs "
            f"n>=5 {large.cited}/{large.turns} = {r_large:.1f}% — gap {gap:+.1f}pp",
        ))
    else:
        results.append((
            "P1 small-corpus cliff (>=10pp)", "UNTESTABLE",
            f"n<=4 has {small.turns} turns, n>=5 has {large.turns}; both sides required",
        ))

    # P2 — size invariance above the cliff
    xs = [float(n) for n in sizes if n >= 5 and by_size[n].turns]
    ys = [100 * by_size[n].cited / by_size[n].turns for n in sizes
          if n >= 5 and by_size[n].turns]
    rho = spearman(xs, ys)
    if rho is None:
        results.append(("P2 size invariance (|rho|<0.4)", "UNTESTABLE", "not enough sizes"))
    else:
        results.append((
            "P2 size invariance (|rho|<0.4)",
            verdict(abs(rho) < 0.4),
            f"Spearman rho(n, citation rate) = {rho:+.3f} over {len(xs)} sizes (n>=5)",
        ))

    # P3 — phantom markers fall with size
    big = Cell()
    for n in sizes:
        if 20 <= n <= 100:
            big.merge(by_size[n])
    a, b = small.markers_per_turn, big.markers_per_turn
    if a is None or b is None or not b:
        results.append(("P3 phantom markers fall (>=2x)", "UNTESTABLE",
                        "no marker data in one side"))
    else:
        results.append((
            "P3 phantom markers fall (>=2x)",
            verdict(a >= 2 * b),
            f"n<=4 {small.dropped_markers}/{small.turns} = {a:.3f}/turn vs "
            f"n in 20..100 {big.dropped_markers}/{big.turns} = {b:.3f}/turn — "
            f"ratio {a / b:.2f}x",
        ))

    # P4 — gating <= 6% in every bin
    worst = max(bins.items(), key=lambda kv: (kv[1].gated / kv[1].turns) if kv[1].turns else 0)
    (wl, wh), wc = worst
    rate = 100 * wc.gated / wc.turns if wc.turns else 0.0
    results.append((
        "P4 gating <=6% every bin",
        verdict(rate <= 6.0),
        f"worst bin {wl}–{wh}: {wc.gated}/{wc.turns} = {rate:.1f}%",
    ))

    # P5 — fabricated quotes <= 3% in every bin
    worst = max(bins.items(),
                key=lambda kv: (kv[1].fabricated / kv[1].turns) if kv[1].turns else 0)
    (fl, fh), fc = worst
    frate = 100 * fc.fabricated / fc.turns if fc.turns else 0.0
    results.append((
        "P5 fabricated quotes <=3% every bin",
        verdict(frate <= 3.0),
        f"worst bin {fl}–{fh}: {fc.fabricated}/{fc.turns} = {frate:.1f}%",
    ))

    # P6 — latency sublinear
    lo = Cell()
    for n in sizes:
        if 1 <= n <= 10:
            lo.merge(by_size[n])
    hi = Cell()
    for n in sizes:
        if 90 <= n <= 100:
            hi.merge(by_size[n])
    if lo.p50 and hi.p50:
        results.append((
            "P6 latency <2x from n<=10 to n>=90",
            verdict(hi.p50 < 2 * lo.p50),
            f"p50 {lo.p50:.2f}s (n 1–10, {len(lo.latencies)} turns) -> "
            f"{hi.p50:.2f}s (n 90–100, {len(hi.latencies)} turns) — "
            f"{hi.p50 / lo.p50:.2f}x",
        ))
    else:
        results.append((
            "P6 latency <2x from n<=10 to n>=90", "UNTESTABLE",
            f"n 1–10 has {len(lo.latencies)} timed turns, n 90–100 has "
            f"{len(hi.latencies)}; both bands required",
        ))

    # P7 — a one-entry journal does not assert relevance
    one = by_size.get(1)
    if one and one.turns:
        r1 = 100 * one.cited / one.turns
        results.append((
            "P7 n=1 citation rate <20%",
            verdict(r1 < 20.0),
            f"{one.cited}/{one.turns} = {r1:.1f}%",
        ))
    else:
        results.append(("P7 n=1 citation rate <20%", "UNTESTABLE", "no n=1 turns"))

    print("| prediction | verdict | evidence |")
    print("|---|---|---|")
    for name, v, evidence in results:
        print(f"| {name} | **{v}** | {evidence} |")

    # ---- violation codes by bin, zero rows included
    print("\n## Violation codes by bin (zero rows kept — 048 R2)\n")
    codes = sorted({c for cell in bins.values() for c in cell.codes})
    if codes:
        print("| code | " + " | ".join(f"{lo}–{hi}" for lo, hi in BINS) + " | report-only |")
        print("|---" * (len(BINS) + 2) + "|")
        for code in codes:
            cells = [str(bins[b].codes.get(code, 0)) for b in BINS]
            flag = "yes" if code in REPORT_ONLY_CODES or code.startswith("gen.") else ""
            print(f"| `{code}` | " + " | ".join(cells) + f" | {flag} |")

    assert len(results) == 7, f"expected 7 predictions, reported {len(results)}"
    held = [name for name, v, _ in results if v == "HELD"]
    failed = [name for name, v, _ in results if v == "FALSIFIED"]
    untested = [name for name, v, _ in results if v == "UNTESTABLE"]
    # Counted apart, because "not evaluated" is not "passed". Subtracting only
    # the falsified ones would have reported a partial run as 6/7 held while
    # four of those six had never been evaluated at all.
    print(f"\n**{len(held)} held · {len(failed)} falsified · "
          f"{len(untested)} untestable**, of {len(results)} pre-registered.")
    if failed:
        print("\nFalsified: " + ", ".join(failed))
    if untested:
        print("\nUntestable on this data: " + ", ".join(untested))
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    return report(Path(sys.argv[1]))


if __name__ == "__main__":
    raise SystemExit(main())
