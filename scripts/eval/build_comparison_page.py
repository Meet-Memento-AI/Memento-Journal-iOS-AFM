#!/usr/bin/env python3
"""Splice the exported aggregates into the comparison page.

The page is a template plus data rather than a generated file, so the HTML
stays reviewable in git and a re-run only changes the JSON blob.

    scripts/eval/build_comparison_page.py --data /tmp/convo-sim.json \
        --template eval-archive/page.template.html \
        --out /tmp/grounding-study-ii.html
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

SENTINEL = "/*__DATA__*/"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--rows-index", type=Path,
                        help="index.json from export_convo_sim_rows.py; its entries become "
                             "DATA.row_files, which is what the page lazy-loads")
    args = parser.parse_args()

    template = args.template.read_text()
    if SENTINEL not in template:
        raise SystemExit(f"{args.template} has no {SENTINEL} to fill")

    # Compact, and with the two sequences that could close the enclosing
    # <script> escaped. A JSON island is parsed as text, so `</script>` inside
    # a string would end the element early and take the page with it.
    data = json.loads(args.data.read_text())
    if args.rows_index:
        data["row_files"] = json.loads(args.rows_index.read_text())
    payload = json.dumps(data, separators=(",", ":"))
    payload = payload.replace("</", "<\\/").replace("<!--", "<\\!--")

    args.out.write_text(template.replace(SENTINEL, payload))
    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size / 1024:.0f} KB, data {len(payload) / 1024:.0f} KB)")
    if size > 16 * 1024 * 1024:
        raise SystemExit("page exceeds the 16MB artifact limit")


if __name__ == "__main__":
    main()
