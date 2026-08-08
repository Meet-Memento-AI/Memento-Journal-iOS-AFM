#!/usr/bin/env python3
"""lint_forbidden_phrases.py  (spec 014 / R3 — REQ-POS-001)

REQ-POS-001 as a checkable CI rule, not a written policy: no in-app string
literal (or App Store metadata) may make an absolute-privacy claim that the
app's PCC routing (spec 017 REQ-INT-003) contradicts. The claim is about the
app's *capability*, not one user's session, so it holds for every shipping build.

Scope (per the spec's acceptance): STRING LITERALS in MeetMemento/**/*.swift,
plus any App Store Connect metadata source (spec 002; scanned if present). The
lint is comment-aware — a `//`/`/* */` comment that merely *mentions* a phrase
(e.g. WelcomeView.swift's note that we never claim it) is NOT a violation; only
a real string literal is.

Exemptions:
  * The REQ-POS-001 positioning claim itself is the rule's source, not a
    violation. Mark its literal with a trailing `// REQ-POS-001-EXEMPT`
    comment, or exempt a whole file with a `// REQ-POS-001-EXEMPT-FILE` line.

Exit non-zero on any violation, naming REQ-POS-001 and spec 014.

Usage: scripts/ci/lint_forbidden_phrases.py [root ...]
       (defaults to MeetMemento + common ASC metadata dirs)
"""
import re
import sys
import os

# Forbidden absolute-privacy phrasings (case-insensitive substring match).
# The first three are verbatim from spec 014 R3; the rest are unambiguous
# equivalents the spec's "or equivalent absolute-privacy phrasing" covers.
FORBIDDEN = [
    "nothing leaves your phone",
    "no network calls",
    "airplane mode proves it",
    "nothing ever leaves your phone",
    "nothing leaves your device",
    "nothing leaves your iphone",
    "never leaves your phone",
    "never leaves your device",
    "never leaves your iphone",
    "no data ever leaves",
    "100% on-device",
    "100% on device",
    "fully offline ai",
    "completely private, always",
]

EXEMPT_LINE = "REQ-POS-001-EXEMPT"
EXEMPT_FILE = "REQ-POS-001-EXEMPT-FILE"


def string_literals_with_lines(src):
    """Yield (line_number, literal_text) for every Swift string literal,
    skipping // and /* */ comments. Handles "..." and \"\"\"...\"\"\" forms."""
    i, n = 0, len(src)
    line = 1
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "\n":
            line += 1
            i += 1
        elif c == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and nxt == "*":
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
        elif c == '"' and src[i:i + 3] == '"""':
            start = line
            i += 3
            buf = []
            while i < n and src[i:i + 3] != '"""':
                if src[i] == "\n":
                    line += 1
                buf.append(src[i])
                i += 1
            i += 3
            yield start, "".join(buf)
        elif c == '"':
            start = line
            i += 1
            buf = []
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == "\n":
                    line += 1
                buf.append(src[i])
                i += 1
            i += 1
            yield start, "".join(buf)
        else:
            i += 1


def scan_swift(path, lines_by_num):
    violations = []
    src = open(path, encoding="utf-8", errors="replace").read()
    if EXEMPT_FILE in src:
        return violations
    for ln, text in string_literals_with_lines(src):
        low = text.lower()
        for phrase in FORBIDDEN:
            if phrase in low:
                raw_line = lines_by_num.get(ln, "")
                if EXEMPT_LINE in raw_line:
                    continue
                violations.append((path, ln, phrase, text.strip()[:80]))
    return violations


def scan_text(path):
    """Plain-text ASC metadata: every line is user-facing copy."""
    violations = []
    for ln, raw in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if EXEMPT_LINE in raw:
            continue
        low = raw.lower()
        for phrase in FORBIDDEN:
            if phrase in low:
                violations.append((path, ln, phrase, raw.strip()[:80]))
    return violations


def main(argv):
    roots = argv[1:] or ["MeetMemento", "fastlane/metadata", "metadata"]
    swift_files, text_files = [], []
    for root in roots:
        if not os.path.exists(root):
            continue
        if os.path.isfile(root):
            (swift_files if root.endswith(".swift") else text_files).append(root)
            continue
        for dirpath, _, names in os.walk(root):
            for name in names:
                p = os.path.join(dirpath, name)
                if name.endswith(".swift"):
                    swift_files.append(p)
                elif name.endswith(".txt"):
                    text_files.append(p)

    violations = []
    for p in sorted(swift_files):
        lines_by_num = {i: l for i, l in enumerate(open(p, encoding="utf-8", errors="replace").read().splitlines(), 1)}
        violations += scan_swift(p, lines_by_num)
    for p in sorted(text_files):
        violations += scan_text(p)

    if violations:
        print("FAIL [REQ-POS-001 / spec 014 R3]: forbidden absolute-privacy phrasing found")
        print("(the app routes to Private Cloud Compute, so these claims are false):\n")
        for path, ln, phrase, ctx in violations:
            print(f'  {path}:{ln}: "{phrase}"  ->  {ctx}')
        print("\nIf this is the REQ-POS-001 positioning claim itself, mark the literal")
        print(f'with a trailing `// {EXEMPT_LINE}` comment.')
        return 1

    scanned = len(swift_files) + len(text_files)
    print(f"OK [REQ-POS-001 / spec 014 R3]: no forbidden phrasing in {scanned} scanned files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
