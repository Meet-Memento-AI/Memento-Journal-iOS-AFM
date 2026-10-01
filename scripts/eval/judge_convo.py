#!/usr/bin/env python3
"""Hosted conversation-quality judge (CQ2 / MEM-334).

Scores synthetic Study-cast turns on Q1–Q4, Q6, Q7 using a frontier model.
**Synthetic transcripts only** — paths under `eval-archive/convo-sim/` or
`calibration/`, with Study persona ids. Never send production user data.

Environment:
  JUDGE_API_KEY   Required for live scoring (OpenAI-compatible API key).
  JUDGE_BASE_URL  Optional; default https://api.openai.com/v1
  JUDGE_MODEL     Optional; default gpt-4o-mini

Examples:
  python3 scripts/eval/judge_convo.py score eval-archive/convo-sim/full-2026-09-24-spec051.jsonl --limit 5 --dry-run
  python3 scripts/eval/judge_convo.py calibrate calibration/conversation-quality-100.csv --dry-run
  python3 scripts/eval/judge_convo.py build-calibration eval-archive/convo-sim/full-2026-09-24-spec051.jsonl -o calibration/conversation-quality-100.csv
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUBRIC_PATH = REPO_ROOT / "docs/eval/conversation-quality-rubric.md"

# Study cast personas (ConversationSimulation); reject anything else.
STUDY_PERSONA = re.compile(r"^p\d{2}-[a-z]+$")

CRITERIA = ("q1", "q2", "q3", "q4", "q6", "q7")

ALLOWED_JSONL_PREFIXES = (
    "eval-archive/convo-sim/",
    "calibration/",
    ".eval-runs/convo-sim/",
)

# Deterministic pseudo-scores for --dry-run and unit tests (1–5 from turn id hash).
def dry_run_scores(turn_id: str) -> dict[str, int]:
    digest = hashlib.sha256(turn_id.encode()).digest()
    out: dict[str, int] = {}
    for index, key in enumerate(CRITERIA):
        out[key] = 1 + (digest[index] % 5)
    return out


def assert_synthetic_jsonl(path: Path) -> None:
    """Refuse paths that are not warehoused synthetic convo-sim exports."""
    try:
        rel = path.resolve().relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise SystemExit(f"Refusing non-repo path (synthetic-only): {path}") from exc
    rel_s = rel.as_posix()
    if not any(rel_s.startswith(prefix) for prefix in ALLOWED_JSONL_PREFIXES):
        raise SystemExit(
            f"Refusing {rel_s}: judge accepts only synthetic Study JSONL under "
            f"{', '.join(ALLOWED_JSONL_PREFIXES)}"
        )


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


def study_persona_ok(persona_id: str | None) -> bool:
    return bool(persona_id and STUDY_PERSONA.match(persona_id))


def extract_scorable_turns(rows: list[dict]) -> list[dict]:
    """Build one record per generated assistant turn with user context."""
    by_run: dict[str, list[dict]] = {}
    for row in rows:
        run_id = row.get("run_id")
        if not run_id:
            continue
        by_run.setdefault(run_id, []).append(row)

    turns: list[dict] = []
    for run_id, messages in sorted(by_run.items()):
        messages.sort(key=lambda r: (r.get("turn_index") or 0, r.get("recorded_at") or ""))
        last_user: str | None = None
        context_users: list[str] = []
        for row in messages:
            role = row.get("role")
            if role == "user":
                text = (row.get("text") or "").strip()
                if text:
                    last_user = text
                    context_users.append(text)
                    if len(context_users) > 4:
                        context_users.pop(0)
            elif role != "assistant":
                continue
            if row.get("error"):
                continue
            if row.get("prompt_version") == "insight-fact@1":
                continue
            model = row.get("model_identifier") or ""
            if not model or model == "swift":
                continue
            persona_id = row.get("persona_id")
            if not study_persona_ok(persona_id):
                continue
            body = (row.get("text") or "").strip()
            if not body or not last_user:
                continue
            turn_index = row.get("turn_index", 0)
            turn_id = f"{run_id}#{turn_index}"
            turns.append(
                {
                    "turn_id": turn_id,
                    "run_id": run_id,
                    "turn_index": turn_index,
                    "persona_id": persona_id,
                    "arm": row.get("arm", ""),
                    "channel": row.get("channel", ""),
                    "user_text": last_user,
                    "context_user_text": "\n---\n".join(context_users[:-1] + [last_user]),
                    "assistant_text": body,
                }
            )
    return turns


def rubric_excerpt() -> str:
    if RUBRIC_PATH.is_file():
        text = RUBRIC_PATH.read_text()
        # Keep prompt size bounded: drop pairwise section for per-turn scoring.
        marker = "## Judge instructions (system)"
        if marker in text:
            return text.split("Pairwise mode")[0].strip()
        return text[:12000]
    return "Score q1,q2,q3,q4,q6,q7 each 1-5. Return JSON only."


def call_judge_api(context_user: str, assistant: str, *, dry_run: bool, turn_id: str) -> dict[str, int]:
    if dry_run:
        return dry_run_scores(turn_id)

    api_key = os.environ.get("JUDGE_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("JUDGE_API_KEY is not set (use --dry-run for offline tests)")

    base = os.environ.get("JUDGE_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    model = os.environ.get("JUDGE_MODEL", "gpt-4o-mini")

    system = rubric_excerpt()
    user_msg = (
        "Recent user messages:\n"
        f"{context_user}\n\n"
        "Assistant reply to score:\n"
        f"{assistant}\n\n"
        f'Return JSON with keys {", ".join(CRITERIA)} (integers 1-5).'
    )
    payload = {
        "model": model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user_msg},
        ],
    }
    request = urllib.request.Request(
        f"{base}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"Judge API HTTP {error.code}: {detail[:500]}") from error

    content = body["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    scores: dict[str, int] = {}
    for key in CRITERIA:
        value = int(parsed[key])
        if value < 1 or value > 5:
            raise ValueError(f"{key} out of range: {value}")
        scores[key] = value
    return scores


def cmd_score(args: argparse.Namespace) -> int:
    path = Path(args.jsonl)
    assert_synthetic_jsonl(path)
    turns = extract_scorable_turns(load_jsonl(path))
    if args.limit:
        turns = turns[: args.limit]

    out_path = Path(args.out) if args.out else None
    writer = csv.DictWriter(
        sys.stdout,
        fieldnames=["turn_id", *CRITERIA],
        extrasaction="ignore",
    ) if not out_path else None
    if out_path:
        fh = out_path.open("w", newline="")
        writer = csv.DictWriter(fh, fieldnames=["turn_id", *CRITERIA])
        writer.writeheader()
    else:
        fh = None
        writer.writeheader()

    for turn in turns:
        scores = call_judge_api(
            turn["context_user_text"],
            turn["assistant_text"],
            dry_run=args.dry_run,
            turn_id=turn["turn_id"],
        )
        row = {"turn_id": turn["turn_id"], **scores}
        writer.writerow(row)

    if fh:
        fh.close()
        print(f"Wrote {len(turns)} rows to {out_path}", file=sys.stderr)
    return 0


def cmd_build_calibration(args: argparse.Namespace) -> int:
    path = Path(args.jsonl)
    assert_synthetic_jsonl(path)
    turns = extract_scorable_turns(load_jsonl(path))
    if len(turns) < args.count:
        raise SystemExit(f"Only {len(turns)} scorable turns in {path}; need {args.count}")

    # Stable sample: sort by turn_id, take every k-th to spread runs.
    turns.sort(key=lambda t: t["turn_id"])
    step = max(1, len(turns) // args.count)
    sample = [turns[i * step] for i in range(args.count)]

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "turn_id",
        "run_id",
        "turn_index",
        "persona_id",
        "arm",
        "channel",
        "user_text",
        "assistant_text",
        *[f"human_a_{c}" for c in CRITERIA],
        *[f"human_b_{c}" for c in CRITERIA],
        *[f"judge_{c}" for c in CRITERIA],
    ]
    with out.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for turn in sample:
            base = {k: turn[k] for k in fields if k in turn}
            writer.writerow(
                {
                    **base,
                    **{f"human_a_{c}": "" for c in CRITERIA},
                    **{f"human_b_{c}": "" for c in CRITERIA},
                    **{f"judge_{c}": "" for c in CRITERIA},
                }
            )
    print(f"Wrote {len(sample)} calibration rows to {out}")
    return 0


def linear_weighted_kappa(rater_a: list[int], rater_b: list[int]) -> float:
    """Cohen's kappa with linear weights for ordinal 1–5 labels."""
    if len(rater_a) != len(rater_b) or not rater_a:
        return 0.0
    categories = sorted(set(rater_a) | set(rater_b))
    n = len(rater_a)
    # Weight matrix
    weights: dict[tuple[int, int], float] = {}
    for i in categories:
        for j in categories:
            weights[(i, j)] = ((i - j) ** 2) / ((max(categories) - min(categories)) ** 2 or 1)

    observed = 0.0
    conf: dict[tuple[int, int], int] = {}
    marg_a: dict[int, int] = {}
    marg_b: dict[int, int] = {}
    for a, b in zip(rater_a, rater_b, strict=True):
        conf[(a, b)] = conf.get((a, b), 0) + 1
        marg_a[a] = marg_a.get(a, 0) + 1
        marg_b[b] = marg_b.get(b, 0) + 1
        observed += weights[(a, b)]
    observed /= n

    expected = 0.0
    for i in categories:
        for j in categories:
            expected += weights[(i, j)] * marg_a.get(i, 0) * marg_b.get(j, 0)
    expected /= n * n

    if expected >= 1.0:
        return 1.0 if observed <= 0 else 0.0
    return 1.0 - observed / expected


def weighted_kappa_mean(rows: list[dict], judge_prefix: str = "judge_") -> tuple[float, dict[str, float]]:
    """Mean linear weighted κ across criteria vs human_a and human_b."""
    per_criterion: dict[str, float] = {}
    for crit in CRITERIA:
        judge_col = f"{judge_prefix}{crit}"
        a_col = f"human_a_{crit}"
        b_col = f"human_b_{crit}"
        judge_vals = []
        a_vals = []
        b_vals = []
        for row in rows:
            j = row.get(judge_col, "").strip()
            if not j:
                continue
            jv = int(j)
            av = row.get(a_col, "").strip()
            bv = row.get(b_col, "").strip()
            if av and bv:
                judge_vals.append(jv)
                a_vals.append(int(av))
                b_vals.append(int(bv))
        if len(judge_vals) < 2:
            per_criterion[crit] = float("nan")
            continue
        ka = linear_weighted_kappa(judge_vals, a_vals)
        kb = linear_weighted_kappa(judge_vals, b_vals)
        per_criterion[crit] = (ka + kb) / 2.0
    finite = [v for v in per_criterion.values() if v == v]
    mean = sum(finite) / len(finite) if finite else float("nan")
    return mean, per_criterion


def cmd_calibrate(args: argparse.Namespace) -> int:
    path = Path(args.csv)
    try:
        rel = path.resolve().relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise SystemExit("Calibration CSV must live in the repo") from exc
    if not rel.as_posix().startswith("calibration/"):
        raise SystemExit("Calibration CSV must be under calibration/")

    with path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))

    filled = 0
    for row in rows:
        need_judge = any(not (row.get(f"judge_{c}") or "").strip() for c in CRITERIA)
        if not need_judge:
            continue
        scores = call_judge_api(
            row.get("user_text") or "",
            row.get("assistant_text") or "",
            dry_run=args.dry_run,
            turn_id=row.get("turn_id") or str(filled),
        )
        for c in CRITERIA:
            row[f"judge_{c}"] = str(scores[c])
        filled += 1

    if args.write_judge and filled:
        fields = rows[0].keys() if rows else []
        with path.open("w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    rated = [
        r for r in rows
        if all((r.get(f"human_a_{c}") or "").strip() for c in CRITERIA)
        and all((r.get(f"human_b_{c}") or "").strip() for c in CRITERIA)
        and all((r.get(f"judge_{c}") or "").strip() for c in CRITERIA)
    ]
    mean_kappa, per = weighted_kappa_mean(rated)
    print(f"Calibration rows with full human+judge labels: {len(rated)} / {len(rows)}")
    for crit, k in per.items():
        label = f"{k:.3f}" if k == k else "n/a"
        print(f"  κ_w({crit}): {label}")
    if mean_kappa == mean_kappa:
        print(f"Mean weighted κ: {mean_kappa:.3f} (threshold {args.threshold})")
        if mean_kappa < args.threshold:
            print("FAIL: below calibration threshold", file=sys.stderr)
            return 1
        print("PASS: calibration threshold met")
    else:
        print(
            "Human raters have not filled human_a_* and human_b_* columns yet; "
            "κ is not computable. Judge columns can still be filled with --write-judge.",
            file=sys.stderr,
        )
        if args.require_kappa:
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Synthetic Study cast conversation judge (CQ2)")
    sub = parser.add_subparsers(dest="command", required=True)

    score_p = sub.add_parser("score", help="Score JSONL turns")
    score_p.add_argument("jsonl", type=Path)
    score_p.add_argument("--limit", type=int, default=0)
    score_p.add_argument("--out", type=Path, default=None)
    score_p.add_argument("--dry-run", action="store_true", help="Deterministic scores, no API")
    score_p.set_defaults(func=cmd_score)

    build_p = sub.add_parser("build-calibration", help="Sample N turns into calibration CSV")
    build_p.add_argument("jsonl", type=Path)
    build_p.add_argument("-o", "--output", type=Path, required=True)
    build_p.add_argument("--count", type=int, default=100)
    build_p.set_defaults(func=cmd_build_calibration)

    cal_p = sub.add_parser("calibrate", help="Fill judge columns and compute κ vs human raters")
    cal_p.add_argument("csv", type=Path)
    cal_p.add_argument("--dry-run", action="store_true")
    cal_p.add_argument("--write-judge", action="store_true", help="Persist judge_* columns to CSV")
    cal_p.add_argument("--threshold", type=float, default=0.6)
    cal_p.add_argument(
        "--require-kappa",
        action="store_true",
        help="Exit 1 unless mean κ >= threshold (default off until humans rate)",
    )
    cal_p.set_defaults(func=cmd_calibrate)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
