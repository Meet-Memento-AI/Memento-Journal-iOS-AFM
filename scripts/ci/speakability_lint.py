#!/usr/bin/env python3
"""speakability_lint.py  (spec 018 / R9 — REQ-VOX-006, P6)

P6 "speakable by construction" enforced mechanically. Every reflection Memento
produces is also spoken by AVSpeechSynthesizer, so markdown, bullets, headings,
emoji, URLs, and blank-line runs read terribly aloud and are forbidden.

This is the CI-engine + reference implementation of the forbidden-pattern list
(technology/06 B6). The in-app Swift `SpeakabilityLinter.validate(_:)` wrapper
(spec 018 R9) is a thin port of these same rules and lands with the intelligence
Swift code (spec 017's PromptRegistry generations). Until the generation pipeline
exists, this engine is exercised via `--selftest` (one fixture per pattern) and,
once spec 022's harness produces fixture-corpus generations, over those.

Modes:
  --selftest                 run the per-pattern fixture suite (CI-runnable today)
  <file ...>                  lint the given generated-prose files (hard-fail)

Exit non-zero on any violation / failed selftest, naming the pattern + REQ-VOX-006.
"""
import re
import sys

# Hard-fail patterns (rejected unconditionally). name -> compiled regex.
HARD_FAIL = {
    "markdown-heading": re.compile(r"(?m)^\s{0,3}#{1,6}\s"),
    "markdown-emphasis-or-code": re.compile(r"(\*|_{1,2}|`)"),
    "list-marker": re.compile(r"(?m)^\s*(?:[-*•]|\d+\.)\s+"),
    "url": re.compile(r"https?://"),
    "blank-line-run": re.compile(r"\n[ \t]*\n[ \t]*\n"),
    "emoji": re.compile(
        "["
        "\U0001F300-\U0001FAFF"
        "\U00002600-\U000027BF"
        "\U0001F1E6-\U0001F1FF"
        "\U00002190-\U000021FF"
        "\U00002B00-\U00002BFF"
        "\U0000FE00-\U0000FE0F"
        "]"
    ),
}


def violations(text):
    """Return list of (pattern_name, matched_snippet)."""
    out = []
    for name, rx in HARD_FAIL.items():
        m = rx.search(text)
        if m:
            snip = m.group(0).replace("\n", "\\n")
            out.append((name, snip))
    return out


# --- Self-test fixtures: each MUST trip exactly the intended pattern; the clean
#     fixtures MUST pass (allowlist: years, clock times, ordinary prose). ---
VIOLATING = {
    "markdown-heading": "# Your week\nYou wrote often.",
    "markdown-emphasis-or-code": "You felt *calmer* this week.",
    "list-marker": "This week:\n- you ran twice\n- you slept well",
    "url": "See https://example.com for more.",
    "blank-line-run": "You wrote on Monday.\n\n\nThen again on Friday.",
    "emoji": "You seemed happy this week \U0001F600",
}
CLEAN = [
    "You wrote three entries this week, mostly in the evening.",
    "In 2026 you started journaling at 9:30 in the morning, and it stuck.",
    "You mentioned your sister twice, both times with warmth.",
    "There was a quieter stretch mid-week, then you picked it back up.",
]


def selftest():
    failed = 0
    for expected, text in VIOLATING.items():
        found = {n for n, _ in violations(text)}
        if expected not in found:
            print(f"  SELFTEST FAIL: fixture for '{expected}' was not detected (found: {found or 'none'})")
            failed += 1
        else:
            print(f"  ok: detects {expected}")
    for text in CLEAN:
        found = violations(text)
        if found:
            print(f"  SELFTEST FAIL: clean fixture flagged {found}: {text!r}")
            failed += 1
    if failed:
        print(f"\nFAIL [REQ-VOX-006 / spec 018 R9]: {failed} selftest case(s) failed")
        return 1
    print(f"\nOK [REQ-VOX-006 / spec 018 R9]: {len(VIOLATING)} pattern detectors + {len(CLEAN)} clean fixtures pass")
    return 0


def lint_files(paths):
    total = 0
    for p in paths:
        text = open(p, encoding="utf-8", errors="replace").read()
        for name, snip in violations(text):
            print(f'  {p}: [{name}] "{snip}"')
            total += 1
    if total:
        print(f"\nFAIL [REQ-VOX-006 / spec 018 R9]: {total} speakability violation(s) in generated prose")
        return 1
    print(f"OK [REQ-VOX-006 / spec 018 R9]: {len(paths)} file(s) clean")
    return 0


def main(argv):
    args = argv[1:]
    if not args or args[0] == "--selftest":
        return selftest()
    return lint_files(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
