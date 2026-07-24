#!/usr/bin/env python3
"""Structural validation for Fixtures/corpus + Fixtures/gold (spec 013 R4).

Checks: entry/question counts, unique IDs, date coverage (>=8 months),
mood/topic vocabulary compliance, class-distribution sanity (restraint gate
needs a large "ordinary" majority), the brother/Dario honesty scrub (no
mention before 2026-03-08), and that every gold question's expectedEntryIDs
exist in the corpus. Also materializes the "derive"-flagged gold questions
(pattern queries with no fixed answer set) into concrete expectedEntryIDs
computed from corpus metadata, writing gold/questions.resolved.json.

Run: python3 Fixtures/validate_corpus.py
Exit code 0 = all checks passed. Non-zero = at least one failure (see output).
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).parent
CORPUS_DIR = ROOT / "corpus"
GOLD_PATH = ROOT / "gold" / "questions.json"
RESOLVED_PATH = ROOT / "gold" / "questions.resolved.json"

MOOD_VOCAB = {
    "anxious", "calm", "frustrated", "hopeful", "tired", "energized",
    "lonely", "connected", "grieving", "content", "restless", "focused",
}
TOPIC_VOCAB = {
    "work", "family", "relationships", "health", "running", "sleep",
    "creativity", "home", "money", "grief", "friends", "weather",
}
VALID_CLASSES = {"ordinary", "anchor", "heavy", "sparse-week"}
VALID_SOURCES = {"voice", "text"}

MIN_ENTRIES = 250
MIN_MONTHS = 8
MIN_GOLD_QUESTIONS = 40
MIN_ORDINARY_FRACTION = 0.60  # spec 022 Gate 4: observation suppressed >= 60%


def fail(msg, errors):
    errors.append(msg)


def warn(msg, warnings):
    warnings.append(msg)


def load_corpus(errors):
    entries = []
    files = sorted(CORPUS_DIR.glob("entries-*.json"))
    if not files:
        fail(f"No corpus files found in {CORPUS_DIR}", errors)
        return entries
    for f in files:
        try:
            data = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            fail(f"{f.name}: invalid JSON ({e})", errors)
            continue
        if not isinstance(data, list):
            fail(f"{f.name}: top-level JSON must be an array", errors)
            continue
        for e in data:
            e["_file"] = f.name
            entries.append(e)
    return entries


def validate_entries(entries, errors, warnings):
    if len(entries) < MIN_ENTRIES:
        fail(f"Corpus has {len(entries)} entries, need >= {MIN_ENTRIES}", errors)

    ids = [e.get("id") for e in entries]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        fail(f"Duplicate entry IDs: {sorted(dupes)}", errors)

    months = set()
    class_counts = {}
    for e in entries:
        eid = e.get("id", "<no id>")
        required = {"id", "createdAt", "source", "transcript", "seedMoods",
                    "seedTopics", "placeName", "weatherSummary", "class"}
        missing = required - set(e.keys())
        if missing:
            fail(f"{eid} ({e['_file']}): missing fields {missing}", errors)
            continue

        try:
            dt = datetime.fromisoformat(e["createdAt"].replace("Z", "+00:00"))
            months.add(dt.strftime("%Y-%m"))
        except ValueError:
            fail(f"{eid}: unparseable createdAt {e['createdAt']!r}", errors)
            continue

        if e["source"] not in VALID_SOURCES:
            fail(f"{eid}: invalid source {e['source']!r}", errors)

        if e["class"] not in VALID_CLASSES:
            fail(f"{eid}: invalid class {e['class']!r}", errors)
        class_counts[e["class"]] = class_counts.get(e["class"], 0) + 1

        for m in e["seedMoods"]:
            if m not in MOOD_VOCAB:
                fail(f"{eid}: mood {m!r} not in fixed vocabulary", errors)
        if len(e["seedMoods"]) > 3:
            fail(f"{eid}: {len(e['seedMoods'])} moods, max 3", errors)

        for t in e["seedTopics"]:
            if t not in TOPIC_VOCAB:
                fail(f"{eid}: topic {t!r} not in fixed vocabulary", errors)
        if len(e["seedTopics"]) > 4:
            fail(f"{eid}: {len(e['seedTopics'])} topics, max 4", errors)

        # Word-count bands are README guidance, not a per-entry contract — natural
        # variation is expected (a sparse-week entry being very short is the point).
        # Advisory only; does not fail the build.
        wc = len(e["transcript"].split())
        if e["class"] in ("ordinary", "sparse-week") and not (10 <= wc <= 140):
            warn(f"{eid}: {wc} words, README guidance is ~40-120 for {e['class']}", warnings)
        if e["class"] in ("anchor", "heavy") and not (70 <= wc <= 300):
            warn(f"{eid}: {wc} words, README guidance is ~120-260 for {e['class']}", warnings)

        for marker in ("#", "* ", "- ", "**"):
            if marker in e["transcript"]:
                fail(f"{eid}: transcript contains markdown marker {marker!r}", errors)

    if len(months) < MIN_MONTHS:
        fail(f"Corpus spans {len(months)} months, need >= {MIN_MONTHS}: {sorted(months)}", errors)

    ordinary_frac = class_counts.get("ordinary", 0) / max(len(entries), 1)
    if ordinary_frac < MIN_ORDINARY_FRACTION:
        fail(
            f"Only {ordinary_frac:.0%} of entries are 'ordinary' "
            f"(need >= {MIN_ORDINARY_FRACTION:.0%} for the restraint gate, spec 022 Gate 4)",
            errors,
        )

    if class_counts.get("heavy", 0) == 0:
        fail("No 'heavy' entries — guardrail refusal-rate measurement needs some", errors)
    if class_counts.get("sparse-week", 0) == 0:
        fail("No 'sparse-week' entries — hasNothingToSay testing needs some", errors)

    return class_counts


def validate_honesty_scrub(entries, errors):
    """No brother/Dario/sibling mention before the 2026-03-08 reopening anchor."""
    pattern = re.compile(r"brother|sibling|dario", re.I)
    for e in entries:
        try:
            dt = datetime.fromisoformat(e["createdAt"].replace("Z", "+00:00"))
        except (ValueError, KeyError):
            continue
        if dt < datetime.fromisoformat("2026-03-08T00:00:00+00:00"):
            if pattern.search(e.get("transcript", "")):
                fail(
                    f"{e.get('id')}: mentions brother/Dario before the "
                    "2026-03-08 reopening anchor — breaks the honesty gold questions",
                    errors,
                )


def load_gold(errors):
    if not GOLD_PATH.exists():
        fail(f"Gold question file not found: {GOLD_PATH}", errors)
        return None
    try:
        return json.loads(GOLD_PATH.read_text())
    except json.JSONDecodeError as e:
        fail(f"gold/questions.json: invalid JSON ({e})", errors)
        return None


def validate_gold(gold, entries_by_id, errors):
    if gold is None:
        return
    questions = gold.get("questions", [])
    if len(questions) < MIN_GOLD_QUESTIONS:
        fail(f"{len(questions)} gold questions, need >= {MIN_GOLD_QUESTIONS}", errors)

    for q in questions:
        for eid in q.get("expectedEntryIDs", []):
            if eid not in entries_by_id:
                fail(f"Gold question {q['id']}: references missing entry {eid!r}", errors)
        if q.get("match") == "none" and q.get("expectedEntryIDs"):
            fail(f"Gold question {q['id']}: match='none' but expectedEntryIDs is non-empty", errors)


def resolve_derived_questions(gold, entries):
    """Materialize 'derive' queries into concrete expectedEntryIDs from corpus metadata."""
    if gold is None:
        return None

    def weekday_name(iso_date):
        return datetime.fromisoformat(iso_date.replace("Z", "+00:00")).strftime("%A")

    resolved = json.loads(json.dumps(gold))  # deep copy
    for q in resolved["questions"]:
        derive = q.get("derive")
        if not derive:
            continue
        matches = []
        for e in entries:
            ok = True
            if "weatherSummary" in derive and e.get("weatherSummary") != derive["weatherSummary"]:
                ok = False
            if ok and "weekday" in derive and weekday_name(e["createdAt"]) != derive["weekday"]:
                ok = False
            if ok and "class" in derive and e.get("class") != derive["class"]:
                ok = False
            if ok and "seedTopics" in derive and derive["seedTopics"] not in e.get("seedTopics", []):
                ok = False
            if ok and "months" in derive and e["createdAt"][:7] not in derive["months"]:
                ok = False
            if ok:
                matches.append(e["id"])
        q["expectedEntryIDs"] = sorted(matches)
        q["_derivedCount"] = len(matches)

    return resolved


def main():
    errors = []
    warnings = []
    entries = load_corpus(errors)
    class_counts = validate_entries(entries, errors, warnings) if entries else {}
    validate_honesty_scrub(entries, errors)

    entries_by_id = {e["id"]: e for e in entries}
    gold = load_gold(errors)
    validate_gold(gold, entries_by_id, errors)

    resolved = resolve_derived_questions(gold, entries)
    if resolved is not None:
        RESOLVED_PATH.write_text(json.dumps(resolved, indent=2) + "\n")
        print(f"Wrote resolved gold set (derive queries materialized) -> {RESOLVED_PATH.relative_to(ROOT)}")

    print(f"\nEntries: {len(entries)}  |  Classes: {class_counts}")
    if gold is not None:
        print(f"Gold questions: {len(gold.get('questions', []))}")

    if warnings:
        print(f"\n{len(warnings)} advisory warning(s) (do not fail the build):")
        for w in warnings:
            print(f"  - {w}")

    if errors:
        print(f"\n{len(errors)} VALIDATION FAILURE(S):")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)

    print("\nAll checks passed.")
    sys.exit(0)


if __name__ == "__main__":
    main()
