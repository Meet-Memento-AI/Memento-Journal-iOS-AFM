#!/usr/bin/env python3
"""Post-hoc: assistant refusals and perceptions spoken in the wrong voice.

NOT pre-registered and NOT part of `ChatEvalScoring`. Adding a scorer mid-study
would change the instrument and break the comparison with Study IV, so this
reads the recorded bodies instead and can be run identically over every archive.

Two patterns, both visible by hand in `.eval-runs/diag/`:

  voice.inverted   the assistant's own epistemic state, attributed to the person
                   — "You can't find an entry that supports that" (it is the
                   assistant that cannot find it), "You don't see anything"

  voice.identityFlip  the person told they are the entity they asked about
                   — "You are Maya" after "Who is Maya?"

Both are grounding failures that every existing code misses: the sentence is
true of *something*, cites nothing it should not, and breaks no formatting rule.
"""
from __future__ import annotations

import argparse
import collections
import json
import re
from pathlib import Path

# The assistant's epistemic verbs. "You can't find an entry" is the giveaway:
# finding an entry is the retrieval layer's job, never the person's.
INVERTED = re.compile(
    r"\bYou (?:can(?:no|')t|could not|couldn't|don'?t|do not)\s+"
    r"(?:find|see|have)\s+"
    r"(?:an?\s+)?(?:entry|entries|anything|any\b|record|note|notes|mention)",
    re.IGNORECASE,
)

# "You are <Capitalised name>" where the name was the subject of the question.
IDENTITY = re.compile(r"\bYou (?:are|were)\s+(?:the\s+)?([A-Z][a-z]{2,})\b")

# Words that make "You are X" an ordinary sentence rather than an identity claim.
IDENTITY_STOP = {
    "The", "A", "An", "Not", "Still", "Already", "Always", "Never", "Here",
    "There", "Now", "Just", "Only", "Both", "Someone", "Somebody", "Trying",
    "Looking", "Asking", "Holding", "Carrying", "Moving", "Sitting", "Standing",
    "Writing", "Reading", "Thinking", "Feeling", "Watching", "Waiting", "Naming",
    "Measuring", "Tracing", "Noticing", "Describing",
}


def scan(path: Path) -> dict:
    per_arm = collections.defaultdict(lambda: {"generated": 0, "inverted": 0,
                                               "identity": 0, "examples": []})
    for line in path.open():
        row = json.loads(line)
        if row.get("role") != "assistant":
            continue
        # Same "generated turn" definition the main analyzer uses: the model
        # actually wrote it.
        if row.get("turn_type") == "error" or row.get("prompt_version") == "insight-fact@1":
            continue
        if not row.get("model_identifier") or row.get("model_identifier") == "swift":
            continue
        body = row.get("text") or ""
        cell = per_arm[row.get("arm", "?")]
        cell["generated"] += 1

        if INVERTED.search(body):
            cell["inverted"] += 1
            if len(cell["examples"]) < 6:
                cell["examples"].append(("inverted", INVERTED.search(body).group(0), body[:200]))

        for m in IDENTITY.finditer(body):
            if m.group(1) in IDENTITY_STOP:
                continue
            cell["identity"] += 1
            if len(cell["examples"]) < 6:
                cell["examples"].append(("identity", m.group(0), body[:200]))
            break

    return dict(per_arm)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+", help="LABEL:path.jsonl")
    ap.add_argument("--examples", action="store_true")
    args = ap.parse_args()

    print("| run | arm | generated | voice.inverted | voice.identityFlip |")
    print("|---|---|---|---|---|")
    stash = []
    for item in args.runs:
        label, _, path = item.partition(":")
        for arm, cell in sorted(scan(Path(path)).items()):
            n = cell["generated"] or 1
            print(f"| {label} | {arm} | {cell['generated']} | "
                  f"{cell['inverted']} ({cell['inverted'] / n:.1%}) | "
                  f"{cell['identity']} ({cell['identity'] / n:.1%}) |")
            stash.append((label, arm, cell))

    if args.examples:
        for label, arm, cell in stash:
            if not cell["examples"]:
                continue
            print(f"\n### {label} / {arm}")
            for kind, hit, body in cell["examples"]:
                print(f"- **{kind}** — `{hit}`\n  > {body}")


if __name__ == "__main__":
    main()
