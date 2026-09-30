#!/usr/bin/env python3
"""check_content_free_logs.py  (Ask 100/100 PS6 — CONSTITUTION §4 rule 3)

AppLogger and PerfSignposts os.Logger calls under Services/Intelligence must stay
content-free: counters, enum codes, and stable identifiers only — never journal
text, questions, prompts, or error messages that may echo user content.

Mark an intentional exception on the log line or the line above with:
  // content-free-log: <reason>

Usage:
  scripts/ci/check_content_free_logs.py
  scripts/ci/check_content_free_logs.py --selftest
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

MODULE = Path(
    os.environ.get("INTELLIGENCE_MODULE_DIR", "withMemento/Services/Intelligence")
)

# Interpolation / argument shapes that may carry journal or message text.
FORBIDDEN_RE = re.compile(
    r"""
    localizedDescription
    | String\s*\(\s*describing\s*:\s*error\b
    | String\s*\(\s*describing\s*:\s*\w*[Ee]rror\b
    | \.(?:text|body|question|quoteText|userText|title)\b
    | \buserTexts\b
    | \btranscript\b
    | \breflection\b
    | \binstructions\b
    | \bpromptLens\b
    """,
    re.VERBOSE,
)

LOG_START = re.compile(
    r"AppLogger\.log\s*\(|"
    r"PerfSignposts\.(?:perfLog|chatLog|speechLog)\.(?:info|debug|error|fault)\s*\("
)

EXEMPT_MARKER = "content-free-log:"
ALLOWLIST_FRAGMENTS = (
    "stats.logLine",
    "rendered.stats.logLine",
    "finding.code",
    "entry.ref",
    "String(describing: intent)",
    "logFields",
)


def strip_swift_comments(src: str) -> str:
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        if src[i : i + 2] == "//":
            while i < n and src[i] != "\n":
                i += 1
        elif src[i : i + 2] == "/*":
            i += 2
            while i < n and src[i : i + 2] != "*/":
                i += 1
            i += 2
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def collect_log_calls(src: str) -> list[tuple[int, str]]:
    """Return (start_line, call_text) for each logging call."""
    calls: list[tuple[int, str]] = []
    i, n = 0, len(src)
    line = 1
    while i < n:
        m = LOG_START.search(src, i)
        if not m:
            break
        start_line = src[: m.start()].count("\n") + 1
        depth = 0
        j = m.start()
        started = False
        while j < n:
            c = src[j]
            if c == "(":
                depth += 1
                started = True
            elif c == ")":
                depth -= 1
                if started and depth == 0:
                    j += 1
                    break
            j += 1
        call_text = src[m.start() : j]
        calls.append((start_line, call_text))
        i = j
    return calls


def line_has_exempt(src: str, start_line: int) -> bool:
    lines = src.splitlines()
    idx = start_line - 1
    for off in (0, -1, -2):
        li = idx + off
        if 0 <= li < len(lines) and EXEMPT_MARKER in lines[li]:
            return True
    return False


def is_allowlisted(call: str) -> bool:
    return any(frag in call for frag in ALLOWLIST_FRAGMENTS)


def scan_file(path: Path) -> list[str]:
    raw = path.read_text(encoding="utf-8")
    violations: list[str] = []
    for start_line, call in collect_log_calls(raw):
        if line_has_exempt(raw, start_line):
            continue
        if is_allowlisted(call):
            continue
        scrubbed = strip_swift_comments(call)
        if FORBIDDEN_RE.search(scrubbed):
            violations.append(f"{path}:{start_line}: content-bearing interpolation in log call")
    return violations


def scan_module(root: Path) -> list[str]:
    if not root.is_dir():
        return [f"FAIL: intelligence module not found at {root}"]
    hits: list[str] = []
    for path in sorted(root.rglob("*.swift")):
        hits.extend(scan_file(path))
    return hits


def selftest() -> None:
    sample = '''
    AppLogger.log("ok counters only")
    AppLogger.log("bad \\(error.localizedDescription)")
    // content-free-log: fixture
    AppLogger.log("exempt \\(error.localizedDescription)")
    AppLogger.log("render \\(rendered.stats.logLine)", type: .info)
    '''
    calls = collect_log_calls(sample)
    assert len(calls) == 4
    violations: list[str] = []
    for start_line, call in calls:
        if line_has_exempt(sample, start_line):
            continue
        if is_allowlisted(call):
            continue
        if FORBIDDEN_RE.search(strip_swift_comments(call)):
            violations.append(f"line {start_line}")
    assert violations == ["line 3"], violations
    print("OK: content-free-logs selftest passed")


def main() -> int:
    if "--selftest" in sys.argv:
        selftest()
        return 0

    root = MODULE
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        root = Path(sys.argv[1])

    violations = scan_module(root)
    if violations and violations[0].startswith("FAIL:"):
        print(violations[0])
        return 1

    if violations:
        print("FAIL [CONSTITUTION §4 rule 3 / PS6]: intelligence logs must be content-free.")
        print("Use counters, codes, and stable ids only — not entry text, questions, prompts,")
        print("or error.localizedDescription. Mark rare exceptions with // content-free-log:")
        for v in violations:
            print(f"  {v}")
        return 1

    print(f"OK: {root} logging calls are content-free.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
