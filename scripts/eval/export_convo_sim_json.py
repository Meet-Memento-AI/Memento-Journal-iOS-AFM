#!/usr/bin/env python3
"""Emit one JSON blob of aggregates for the comparison page.

The page embeds this rather than the JSONL: the two runs together are about
10 MB of per-message records, and a browser has no business parsing that to
draw eight charts. Every number here comes from `analyze_convo_sim`'s own
definitions, imported rather than re-implemented, so the page and the CLI
report cannot drift apart.

    scripts/eval/export_convo_sim_json.py \
        --run "Study I:eval-archive/convo-sim/full-2026-09-20.jsonl" \
        --run "Study II:eval-archive/convo-sim/full-2026-09-21-persona.jsonl" \
        --out /tmp/convo-sim.json
"""
from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import re
import statistics
from pathlib import Path

# A month-name-plus-day assertion in the reply body. No scorer targets these, so
# the count has to be derived from the text; on a zero-entry arm every one of
# them is invented by construction, which is the number that should be zero.
# Shape of the reply as a reader meets it. Computed from the text rather than
# from recorded fields, because the fields arrived over three studies and the
# earliest run has none of them — a shape comparison has to be measured the same
# way on all three or it is not a comparison.
SHAPE_PATTERNS = {
    "heading": re.compile(r"(^|\n)#{1,4}\s"),
    "italics": re.compile(r"(?<!\*)\*(?!\*)[^*\n]{3,}?(?<!\*)\*(?!\*)"),
    "bold": re.compile(r"\*\*[^*\n]{2,}?\*\*"),
    "list": re.compile(r"(^|\n)\s*([-*+]|\d+\.)\s"),
    "marker_leak": re.compile(r"\{\{|\[Evidence\]|\[Today:|\[ref\s"),
}

DATE_ASSERTION = re.compile(
    r"\b(January|February|March|April|May|June|July|August|September|October|November|December)"
    r"\s+\d{1,2}\b",
    re.IGNORECASE,
)

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("acs", HERE / "analyze_convo_sim.py")
acs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acs)


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(q * len(ordered)))]


def arm_block(rows: list[dict], arm: str) -> dict:
    gen = acs.generated(rows, arm)
    total = len(gen)
    cited = [r for r in gen if r.get("citations")]
    ages = [c["entry_age_days"] for r in cited for c in r["citations"] if "entry_age_days" in c]
    secs = [r["seconds"] for r in gen if "seconds" in r]
    before = [r for r in gen if not r.get("history_truncated")]
    after = [r for r in gen if r.get("history_truncated")]
    assistant = [r for r in rows if r.get("role") == "assistant" and r.get("arm") == arm]

    runs = collections.defaultdict(list)
    for row in rows:
        if row.get("arm") == arm:
            runs[row["run_id"]].append(row)

    return {
        "arm": arm,
        # Counted, not doubled from the assistant count: a conversation can end
        # on an unanswered user turn, so the two are not always in step.
        "messages": sum(1 for r in rows if r.get("arm") == arm),
        "generated": total,
        "assistant_turns": len(assistant),
        "errors": sum(1 for r in assistant if r.get("error")),
        "swift_computed": sum(1 for r in assistant if r.get("prompt_version") == "insight-fact@1"),
        "conversations": len(runs),
        # Rates are gating-only, matching ChatEvalScoring.gating: `gen.*` is
        # shape telemetry and the three unarmed `hall.*` codes are measured but
        # do not gate. The raw code counts below carry them separately.
        "gating_violations": sum(acs.violated(r) for r in gen),
        "invented_material": sum(
            any(v["code"] in acs.FABRICATION_CODES for v in r.get("violations", [])) for r in gen
        ),
        "notebook": sum(1 for r in gen if r.get("channel") == "notebook"),
        "cited_turns": len(cited),
        "citations": sum(len(r["citations"]) for r in cited),
        "median_cited_entry_age_days": statistics.median(ages) if ages else None,
        "codes": dict(collections.Counter(
            v["code"] for r in gen for v in r.get("violations", [])
        )),
        "channels": dict(collections.Counter(r.get("channel") for r in gen if r.get("channel"))),
        "latency": {
            "n": len(secs),
            "p50": percentile(secs, 0.5),
            "p90": percentile(secs, 0.9),
            "max": max(secs) if secs else None,
        },
        "degraded": sum(1 for r in gen if r.get("was_degraded")),
        "designed_refusals": sum(1 for r in rows if r.get("arm") == arm and r.get("designed_refusal")),
        "history_window": {
            "before_n": len(before),
            "before_rate": 100 * sum(acs.violated(r) for r in before) / len(before) if before else None,
            "after_n": len(after),
            "after_rate": 100 * sum(acs.violated(r) for r in after) / len(after) if after else None,
        },
        # Spec 050 R7's counters. These are the only window onto what the MODEL
        # emitted: `AskResult` carries the rendered body, so a clean product
        # figure cannot by itself distinguish a model that improved from a
        # renderer that cleaned up after one that did not.
        "render": (lambda packed: {
            "turns_with_pack": len(packed),
            "matched": sum(1 for r in packed if r["evidence_pack"].get("state") == "matched"),
            # Of the turns that HAD evidence to point at, how many pointed?
            "expanded_quote_turns": sum(
                1 for r in packed if r["evidence_pack"].get("expanded_quotes")),
            "expanded_date_turns": sum(
                1 for r in packed if r["evidence_pack"].get("expanded_dates")),
            # Cleanup the renderer had to do — the model reaching for the old
            # vehicles, or quoting something nothing backs.
            "turns_needing_cleanup": sum(
                1 for r in packed
                if (r["evidence_pack"].get("adopted_quotes", 0)
                    + r["evidence_pack"].get("stripped_italics", 0)
                    + r["evidence_pack"].get("dropped_quotations", 0)) > 0),
            "totals": {
                key: sum(r["evidence_pack"].get(key, 0) for r in packed)
                for key in ("slots", "adopted_quotes", "dropped_markers", "duplicate_quotes",
                            "stripped_italics", "dropped_quotations", "unwrapped_bold",
                            "stripped_dates", "dropped_headings")
            },
            "fallbacks": sum(1 for r in packed if r["evidence_pack"].get("fallback")),
            "chips": sum(r.get("chips", 0) for r in gen),
        })([r for r in gen if r.get("evidence_pack")]),
        "render_versions": sorted({r["render_version"] for r in gen if r.get("render_version")}),
        "prompt_versions": sorted({r["prompt_version"] for r in gen if r.get("prompt_version")}),
        "output_shape": (lambda bodies: {
            "n": len(bodies),
            "median_words": statistics.median([len(b.split()) for b in bodies]) if bodies else None,
            "mean_words": (sum(len(b.split()) for b in bodies) / len(bodies)) if bodies else None,
            "questions_per_reply": (sum(b.count("?") for b in bodies) / len(bodies)) if bodies else None,
            **{
                f"pct_{name}": (100 * sum(1 for b in bodies if pattern.search(b)) / len(bodies))
                if bodies else None
                for name, pattern in SHAPE_PATTERNS.items()
            },
        })([r.get("text") or "" for r in gen]),
        "date_assertions": (lambda dated: {
            "n": len(dated),
            "rate": 100 * len(dated) / total if total else None,
            # Unflagged by any gating code: the failure is invisible to the suite.
            "unflagged": sum(1 for r in dated if not acs.violated(r)),
        })([r for r in gen if DATE_ASSERTION.search(r.get("text") or "")]),
        "median_conversation_length": statistics.median([len(t) for t in runs.values()]) if runs else None,
        "fallback_person_turns": sum(
            1 for r in rows if r.get("arm") == arm and r.get("move") == "fallback"
        ),
    }


def per_field(rows: list[dict], arms: list[str], field: str) -> list[dict]:
    out = []
    for value in sorted({r.get(field) for r in acs.generated(rows) if r.get(field)}):
        entry = {"key": value}
        for arm in arms:
            cell = [r for r in acs.generated(rows, arm) if r.get(field) == value]
            hits = sum(acs.violated(r) for r in cell)
            entry[arm] = {
                "n": len(cell),
                "hits": hits,
                "rate": 100 * hits / len(cell) if cell else None,
            }
        out.append(entry)
    return out


def examples(rows: list[dict], code: str, limit: int = 8) -> list[dict]:
    """A handful of real spans per code.

    A rate is not evidence on its own: `hall.fabricatedQuote` at 46% could be a
    model inventing entries or a scorer mis-defining a quote, and only the text
    settles which. The page carries these so a reader can judge instead of
    taking the number on trust.
    """
    seen, out = set(), []
    for row in rows:
        if row.get("role") != "assistant":
            continue
        for violation in row.get("violations", []):
            if violation["code"] != code:
                continue
            detail = violation.get("detail", "")
            if detail in seen:
                continue
            seen.add(detail)
            out.append({
                "arm": row.get("arm"),
                "detail": detail,
                "body": row.get("text", "")[:400],
                "channel": row.get("channel"),
                "turn_type": row.get("turn_type"),
                "persona_id": row.get("persona_id"),
                "cited": len(row.get("citations", [])),
            })
            if len(out) >= limit:
                return out
    return out


def run_block(label: str, path: Path) -> dict:
    rows = acs.load(path)
    manifest_path = path.with_suffix(".manifest.json")
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    arms = [a["name"] for a in manifest.get("arms", [])] or sorted(
        {r.get("arm") for r in rows if r.get("arm")}
    )
    assistant = [r for r in rows if r.get("role") == "assistant"]

    seen_turns = {r.get("turn_type") for r in assistant if r.get("turn_type")}
    matrix = []
    for turn in list(acs.TURN_TYPES) + sorted(seen_turns - set(acs.TURN_TYPES)):
        cells = {
            channel: sum(
                1 for r in assistant
                if r.get("turn_type") == turn and r.get("channel") == channel
            )
            for channel in acs.REPLY_CHANNELS
        }
        matrix.append({
            "turn_type": turn,
            "cells": cells,
            "total": sum(cells.values()),
            "rate": 100 * sum(cells.values()) / len(assistant) if assistant else 0,
        })

    def opener_sample(arm: str) -> dict | None:
        """The first reply of run 000 on this arm.

        Run ids are seeded identically across studies, so this is the same
        persona answering the same opening question in every study — the only
        genuinely paired comparison the series has, since every later turn
        depends on what the assistant said before it.
        """
        pool = [r for r in rows if r.get("arm") == arm and r.get("run_id", "").endswith("/000")]
        user = next((r for r in pool if r.get("role") == "user" and r.get("turn_index") == 0), None)
        reply = next((r for r in pool if r.get("role") == "assistant" and r.get("turn_index") == 1), None)
        if not reply:
            return None
        return {
            "arm": arm,
            "question": (user or {}).get("text", ""),
            "reply": reply.get("text", ""),
            "channel": reply.get("channel"),
            "intent": reply.get("intent_id"),
            "persona": reply.get("persona_id"),
            "citations": len(reply.get("citations") or []),
            "codes": [v["code"] for v in reply.get("violations", [])],
        }

    return {
        "label": label,
        "file": path.name,
        "openers": [s for s in (opener_sample(a) for a in arms) if s],
        "messages": len(rows),
        "manifest": {
            key: manifest.get(key) for key in (
                "label", "started_at", "finished_at", "git_sha", "git_branch",
                "os_version", "runs_per_arm", "min_messages", "max_messages",
                "history_message_limit", "notes", "scorers",
            ) if manifest.get(key) is not None
        },
        "complete": "finished_at" in manifest,
        "arms_meta": [
            {
                "name": a["name"],
                "entry_count": a.get("entry_count"),
                "entry_date_range": a.get("entry_date_range") or None,
            }
            for a in manifest.get("arms", [])
        ],
        "arms": [arm_block(rows, arm) for arm in arms],
        "turn_matrix": matrix,
        "personas": per_field(rows, arms, "persona_id"),
        "intents": per_field(rows, arms, "intent_id"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="append", required=True,
                        help="LABEL:path/to/run.jsonl")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    runs, all_rows = [], []
    for item in args.run:
        label, _, path = item.partition(":")
        path = Path(path)
        runs.append(run_block(label, path))
        all_rows.extend(acs.load(path))

    payload = {
        "runs": runs,
        "fabrication_codes": list(acs.FABRICATION_CODES),
        "report_only_codes": list(acs.REPORT_ONLY_CODES),
        "turn_types": list(acs.TURN_TYPES),
        "reply_channels": list(acs.REPLY_CHANNELS),
        "examples": {
            code: examples(all_rows, code)
            for code in ("hall.fabricatedQuote", "hall.uncitedQuote", "rule.boldNotTheirWords")
        },
    }
    args.out.write_text(json.dumps(payload, indent=1))
    print(f"wrote {args.out} ({args.out.stat().st_size / 1024:.0f} KB)")
    for run in runs:
        state = "complete" if run["complete"] else "PARTIAL"
        print(f"  {run['label']}: {run['messages']} messages, {state}, "
              f"arms {[a['arm'] for a in run['arms']]}")


if __name__ == "__main__":
    main()
