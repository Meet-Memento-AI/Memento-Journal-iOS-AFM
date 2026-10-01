#!/usr/bin/env python3
"""Build stratified turn-kind gold fixture from Study III convo-sim archive.

Reads eval-archive/convo-sim/full-2026-09-23-resim.jsonl, applies the cast
labelling rubric (see internal ask-chat-100/mem-333-rt1-turn-kind-baseline.md),
replays per-run history for hasHistory / lastAssistantAskedQuestion, and writes
withMementoTests/Fixtures/turn-kind/cast-gold.json (≥300 rows).

Regenerate after changing the rubric or source archive:

  python3 scripts/eval/build_turn_kind_fixture.py
"""

from __future__ import annotations

import hashlib
import json
import random
import re
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "eval-archive/convo-sim/full-2026-09-23-resim.jsonl"
OUT = REPO / "withMementoTests/Fixtures/turn-kind/cast-gold.json"
MIN_ROWS = 300
MOVE_QUOTA_PER_GOLD = 12  # after all openers, stratify moves by gold kind

INTENT_GOLD = {
    "i01-broad-recall": "journalQuery",
    "i02-entity-recall": "journalQuery",
    "i03-temporal": "journalQuery",
    "i04-nomatch-bait": "journalQuery",
    "i05-small-talk": "social",
    "i06-venting": "share",
    "i07-correction": "correction",
    "i08-multi-hop": "journalQuery",
    "i09-advice-seeking": "reflectiveQuestion",
    "i10-crisis-adjacent": "share",
}

MOVE_GOLD = {
    "Refer back to something from earlier in this conversation, and correct a detail of it.": "followup",
    "Push back. Tell it the last reply was too vague, or that it got something wrong.": "correction",
    "Ask the assistant something about your own journal or your own past.": "journalQuery",
    "Ask the assistant to do something a journalling app probably should not do.": "offdomain",
    "Ask a direct question and make clear you want an actual answer, not another question.": "followup",
    "Go quiet — reply in three or four words, no more.": "acknowledgement",
    "Disagree with how the assistant characterised you.": "correction",
    "Wrap the conversation up. Say goodbye in whatever way this person would.": "social",
    "Answer briefly, and bring in one concrete new detail that has not come up yet.": "share",
    "Change the subject to something else going on in your life this week.": "share",
    "Name a feeling you have not named yet in this conversation.": "share",
    "Make a small joke or an aside that has nothing to do with the last message.": "share",
    "Tell a short story about something that happened today.": "share",
}


def last_assistant_asked_question(text: str | None) -> bool:
    if not text or "?" not in text:
        return False
    q = text.rindex("?")
    up_to_q = text[: q + 1]
    for sep in (".", "!", "\n"):
        if sep in up_to_q:
            start = up_to_q.rindex(sep)
            if start < q:
                up_to_q = up_to_q[start + 1 :]
                break
    return bool(up_to_q.strip())


def gold_for_user(u: dict) -> tuple[str | None, str | None]:
    move = u.get("move")
    if u.get("turn_index") == 0:
        return INTENT_GOLD.get(u.get("intent_id")), "cast_intent_opener"
    if move == "fallback":
        return "followup", "cast_fallback_script"
    if move in MOVE_GOLD:
        return MOVE_GOLD[move], "cast_move"
    return None, None


def row_id(run_id: str, turn_index: int, text: str) -> str:
    h = hashlib.sha256(f"{run_id}|{turn_index}|{text[:240]}".encode()).hexdigest()
    return h[:16]


def load_labelled_rows() -> list[dict]:
    by_run: dict[str, list[dict]] = defaultdict(list)
    for line in SOURCE.read_text().splitlines():
        if not line.strip():
            continue
        by_run_key = json.loads(line)
        by_run[by_run_key["run_id"]].append(by_run_key)

    labelled: list[dict] = []
    for run_id in sorted(by_run.keys()):
        rows = by_run[run_id]
        last_assistant_text: str | None = None
        for i, row in enumerate(rows):
            if row.get("role") != "user":
                if row.get("role") == "assistant":
                    last_assistant_text = row.get("text") or ""
                continue
            gold, source = gold_for_user(row)
            if not gold:
                continue
            hist = 0
            if i + 1 < len(rows) and rows[i + 1].get("role") == "assistant":
                hist = int(rows[i + 1].get("history_messages") or 0)
            has_history = hist > 0
            last_q = last_assistant_asked_question(last_assistant_text) if has_history else False
            labelled.append(
                {
                    "id": row_id(run_id, row.get("turn_index", 0), row.get("text", "")),
                    "text": row.get("text", ""),
                    "goldTurnKind": gold,
                    "hasHistory": has_history,
                    "lastAssistantAskedQuestion": last_q,
                    "labelSource": source,
                    "intentId": row.get("intent_id"),
                    "personaId": row.get("persona_id"),
                    "arm": row.get("arm"),
                    "move": row.get("move"),
                    "turnIndex": row.get("turn_index"),
                }
            )
            if i + 1 < len(rows) and rows[i + 1].get("role") == "assistant":
                last_assistant_text = rows[i + 1].get("text") or ""
    return labelled


def stratified_sample(all_rows: list[dict]) -> list[dict]:
    openers = [r for r in all_rows if r["labelSource"] == "cast_intent_opener"]
    moves = [r for r in all_rows if r["labelSource"] == "cast_move"]
    fallbacks = [r for r in all_rows if r["labelSource"] == "cast_fallback_script"]

    chosen: list[dict] = list(openers)
    seen = {r["id"] for r in chosen}

    by_gold: dict[str, list[dict]] = defaultdict(list)
    for r in moves:
        by_gold[r["goldTurnKind"]].append(r)

    rng = random.Random(0x525431)
    for gold in sorted(by_gold.keys()):
        pool = by_gold[gold]
        rng.shuffle(pool)
        n = 0
        for r in pool:
            if r["id"] in seen:
                continue
            if n >= MOVE_QUOTA_PER_GOLD:
                break
            chosen.append(r)
            seen.add(r["id"])
            n += 1

    for r in fallbacks:
        if r["id"] not in seen:
            chosen.append(r)
            seen.add(r["id"])

    if len(chosen) < MIN_ROWS:
        rng.shuffle(moves)
        for r in moves:
            if r["id"] in seen:
                continue
            chosen.append(r)
            seen.add(r["id"])
            if len(chosen) >= MIN_ROWS:
                break

    chosen.sort(key=lambda r: (r.get("arm", ""), r.get("personaId", ""), r.get("turnIndex", 0), r["id"]))
    return chosen


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing source archive: {SOURCE}")
    all_rows = load_labelled_rows()
    rows = stratified_sample(all_rows)
    if len(rows) < MIN_ROWS:
        raise SystemExit(f"Only {len(rows)} rows after stratification (need {MIN_ROWS})")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "source": "eval-archive/convo-sim/full-2026-09-23-resim.jsonl",
        "study": "Study III resim",
        "rowCount": len(rows),
        "labelling": "ConvoSimCast intent + move rubric (cast-complete, not human-rated)",
        "rows": rows,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
