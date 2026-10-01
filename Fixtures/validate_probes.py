#!/usr/bin/env python3
"""Structural validation for Fixtures/probes (MEM-326 / T7 + CQ3).

Run: python3 Fixtures/validate_probes.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).parent
PROBES = ROOT / "probes"

MIN_BENIGN = 60
REQUIRED_CRISIS_LOCALES = {
    "es", "fr", "de", "pt-BR", "it", "ja", "zh-Hans", "ko",
}


def load(name):
    path = PROBES / name
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text())


def main():
    errors = []
    benign = load("q9-benign-hard-topic.json")
    probes = benign.get("probes", [])
    if len(probes) < MIN_BENIGN:
        errors.append(f"q9-benign-hard-topic: need >= {MIN_BENIGN}, got {len(probes)}")
    ids = [p.get("id") for p in probes]
    if len(ids) != len(set(ids)):
        errors.append("q9-benign-hard-topic: duplicate ids")

    regulated = load("regulated.json").get("probes", [])
    if len(regulated) < 8:
        errors.append(f"regulated.json: need >= 8 probes, got {len(regulated)}")

    inj = load("injection.json")
    if len(inj.get("userJailbreaks", [])) < 3:
        errors.append("injection.json: need >= 3 userJailbreaks")
    if len(inj.get("entryInjections", [])) < 1:
        errors.append("injection.json: need >= 1 entryInjections")

    mc = load("multilingual-crisis.json").get("probes", [])
    locales = {p.get("locale") for p in mc}
    missing = REQUIRED_CRISIS_LOCALES - locales
    if missing:
        errors.append(f"multilingual-crisis.json: missing locales {sorted(missing)}")
    for loc in REQUIRED_CRISIS_LOCALES:
        n = sum(1 for p in mc if p.get("locale") == loc)
        if n < 1:
            errors.append(f"multilingual-crisis.json: locale {loc} has no probes")

    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
    print(
        f"OK: {len(probes)} benign, {len(regulated)} regulated, "
        f"{len(mc)} multilingual crisis ({len(locales)} locales)"
    )


if __name__ == "__main__":
    main()
