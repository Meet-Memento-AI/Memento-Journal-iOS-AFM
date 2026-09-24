#!/usr/bin/env python3
"""Emit each run's rows as a same-origin JS file the page can load on demand.

Not JSON fetched at runtime: an artifact's CSP is explicit about which hosts
scripts and stylesheets may come from and blocks fetch/XHR broadly, so a script
assigning to a global is the load path that is actually guaranteed to work. It
is also lazy — the page injects the tag only when someone opens the browser, so
the 10 MB never costs a reader who only wants the charts.

    scripts/eval/export_convo_sim_rows.py \
        --run "Study I:eval-archive/convo-sim/full-2026-09-20.jsonl" \
        --run "Study II:eval-archive/convo-sim/full-2026-09-21-persona.jsonl" \
        --out-dir eval-archive/rows
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def slug(label: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in label).strip("-")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="append", required=True, help="LABEL:path.jsonl")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    index = []
    for item in args.run:
        label, _, path = item.partition(":")
        rows = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
        name = f"{slug(label)}.js"
        # One row per line keeps the file diffable and lets a human read it
        # without a formatter; `JSON.parse` of one big string beats a JS array
        # literal for parse time at this size.
        body = "\n".join(json.dumps(row, separators=(",", ":")) for row in rows)
        # The payload rides as a JSON string, so the only sequences that can
        # break out are the ones JSON itself escapes; `</script` cannot occur
        # inside a JSON string literal once `<\/` substitution is applied.
        encoded = json.dumps(body).replace("</", "<\\/")
        out = args.out_dir / name
        out.write_text(
            "window.__CONVO_RAW = window.__CONVO_RAW || {};\n"
            f"window.__CONVO_RAW[{json.dumps(label)}] = "
            f"{encoded}.split('\\n').map(function (l) {{ return JSON.parse(l); }});\n"
        )
        index.append({"label": label, "file": f"rows/{name}", "rows": len(rows),
                      "bytes": out.stat().st_size, "source": Path(path).name})
        print(f"  {label}: {len(rows)} rows -> {out} ({out.stat().st_size / 1048576:.1f} MB)")

    (args.out_dir / "index.json").write_text(json.dumps(index, indent=1))
    total = sum(entry["bytes"] for entry in index)
    print(f"total {total / 1048576:.1f} MB across {len(index)} files")
    for entry in index:
        if entry["bytes"] > 16 * 1024 * 1024:
            raise SystemExit(f"{entry['file']} exceeds the 16MB per-file limit")


if __name__ == "__main__":
    main()
