#!/usr/bin/env python3
"""T2 (MEM-324) — build renderer replay fixtures from a warehoused convo-sim run.

Study VI is the default source (`eval-archive/convo-sim/full-2026-09-27-tier.jsonl`).
Rows are assistant generations only (same filter as `analyze_convo_sim.generated`).

Until T1 adds `rawBody` on synthetic runs, fixtures carry **rendered** `text` only.
`RendererReplayTests` re-scores that surface with `ChatEvalScoring` and compares
aggregate gating counts to `baseline-violation-counts.json`. True
`ReplyRenderer.render` replay uses `raw-samples.json` and turns on when `rawBody`
is present on warehouse rows.

    python3 scripts/eval/regen_renderer_replay_fixtures.py
    python3 scripts/eval/regen_renderer_replay_fixtures.py --check

`--check` fails if committed fixtures or baseline would change (merge CI).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_JSONL = REPO / "eval-archive/convo-sim/full-2026-09-27-tier.jsonl"
OUT_DIR = REPO / "withMementoTests/Fixtures/replay"
TURNS_PATH = OUT_DIR / "study-vi-turns.jsonl"
MANIFEST_PATH = OUT_DIR / "manifest.json"
BASELINE_PATH = OUT_DIR / "baseline-violation-counts.json"

REPORT_ONLY = frozenset({
    "hall.fabricatedQuote",
    "hall.firstPersonPerception",
    "hall.narrativeJoin",
    "hall.unbackedDate",
})


def generated(rows: list[dict]) -> list[dict]:
    return [
        row for row in rows
        if row.get("role") == "assistant"
        and not row.get("error")
        and row.get("prompt_version") != "insight-fact@1"
    ]


def gating_codes(row: dict) -> list[str]:
    out: list[str] = []
    for violation in row.get("violations") or []:
        code = violation.get("code") or ""
        if code.startswith("gen.") or code in REPORT_ONLY:
            continue
        if code.startswith(("leak.", "rule.", "hall.", "gold.", "insight.")):
            out.append(code)
    return out


def compact_turn(row: dict) -> dict:
    """Fields `RendererReplayTests` needs to re-score a turn."""
    compact: dict = {
        "id": f"{row.get('run_id', '')}:{row.get('turn_index', 0)}",
        "arm": row.get("arm"),
        "channel": row.get("channel"),
        "turn_type": row.get("turn_type"),
        "response_policy": row.get("response_policy"),
        "evidence_state": row.get("evidence_state"),
        "prompt_version": row.get("prompt_version"),
        "body": row.get("text") or "",
        "archived_gating": gating_codes(row),
    }
    if row.get("rawBody"):
        compact["rawBody"] = row["rawBody"]
    citations = row.get("citations") or []
    if citations:
        compact["citations"] = [
            {
                "entry_uuid": c.get("entry_uuid"),
                "entry_created_at": c.get("entry_created_at"),
                "excerpt": c.get("excerpt", ""),
            }
            for c in citations
        ]
    facts = row.get("facts") or []
    if facts:
        compact["facts"] = facts
    return compact


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as error:
            print(f"  ! {path.name}:{number} skipped ({error})", file=sys.stderr)
    return rows


def write_outputs(jsonl: Path) -> None:
    rows = load_jsonl(jsonl)
    turns = [compact_turn(row) for row in generated(rows)]
    gating = Counter()
    for row in generated(rows):
        gating.update(gating_codes(row))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with TURNS_PATH.open("w", encoding="utf-8") as handle:
        for turn in turns:
            handle.write(json.dumps(turn, ensure_ascii=False, separators=(",", ":")))
            handle.write("\n")

    manifest = {
        "source_jsonl": str(jsonl.relative_to(REPO)),
        "source_sha256": hashlib.sha256(jsonl.read_bytes()).hexdigest(),
        "turn_count": len(turns),
        "rendered_only": not any(t.get("rawBody") for t in turns),
        "notes": (
            "Rendered bubble text only until T1 (MEM-322) records rawBody on "
            "synthetic runs. Gating baseline is archived violations at extract "
            "time; Swift re-score is checked in RendererReplayTests on CI."
        ),
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    baseline = {
        "source_jsonl": manifest["source_jsonl"],
        "source_sha256": manifest["source_sha256"],
        "turn_count": len(turns),
        "rendered_only": manifest["rendered_only"],
        "gating_counts": dict(sorted(gating.items())),
        "gating_total": sum(gating.values()),
    }
    BASELINE_PATH.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(turns)} turns → {TURNS_PATH.relative_to(REPO)}")
    print(f"Gating total (archived): {baseline['gating_total']} across {len(gating)} codes")


def check_outputs() -> int:
    if not DEFAULT_JSONL.is_file():
        print(f"FAIL: missing {DEFAULT_JSONL}", file=sys.stderr)
        return 1
    before = {
        TURNS_PATH: TURNS_PATH.read_text() if TURNS_PATH.is_file() else None,
        MANIFEST_PATH: MANIFEST_PATH.read_text() if MANIFEST_PATH.is_file() else None,
        BASELINE_PATH: BASELINE_PATH.read_text() if BASELINE_PATH.is_file() else None,
    }
    write_outputs(DEFAULT_JSONL)
    failed = False
    for path, old in before.items():
        new = path.read_text()
        if old != new:
            print(f"FAIL: {path.relative_to(REPO)} is stale. Re-run regen_renderer_replay_fixtures.py")
            failed = True
    if failed:
        return 1
    print("OK: renderer replay fixtures and baseline match the Study VI archive.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--jsonl",
        type=Path,
        default=DEFAULT_JSONL,
        help="Warehoused convo-sim JSONL (default: Study VI tier run)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 if committed fixture outputs would change",
    )
    args = parser.parse_args()
    if args.check:
        return check_outputs()
    if not args.jsonl.is_file():
        print(f"FAIL: {args.jsonl} not found", file=sys.stderr)
        return 1
    write_outputs(args.jsonl)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
