#!/usr/bin/env python3
"""Keep only SwiftLint findings that land on lines a change added or modified.

Usage: filter_lint_to_lines.py <added-lines-file> <swiftlint-output> <repo-root>

<added-lines-file> holds one "path:line" per line (repo-relative), as produced
by lint_changed_swift.sh from `git diff --unified=0`. SwiftLint prints absolute
paths, so they are made repo-relative before matching.
"""
import sys

added_path, lint_path, root = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("/") + "/"
added = set(open(added_path).read().split())

for line in open(lint_path):
    parts = line.split(":", 2)
    if len(parts) < 3 or not parts[1].isdigit():
        continue
    path = parts[0][len(root):] if parts[0].startswith(root) else parts[0]
    if f"{path}:{parts[1]}" in added:
        print(line.rstrip())
