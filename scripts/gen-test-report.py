#!/usr/bin/env python3
"""Test-report generator: JSONL check results -> Markdown report.

Input: one JSON object per line, as emitted by the checks' --json mode:
  {"check": ..., "status": "PASS|FAIL|NOT RUN|BLOCKED", "target": ...,
   "details": [...]}
Extra entries may be appended with --extra 'check=status: note' (repeatable)
for manual gates (hardware tests, diffoscope) that cannot run on the host.

Output follows docs/test-results/TEMPLATE.md.
"""

import argparse
import datetime
import json
import os
import sys

ORDER = {"FAIL": 0, "BLOCKED": 1, "NOT RUN": 2, "PASS": 3}


def load_results(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def parse_extra(spec):
    # "check=status: note"
    name, rest = spec.split("=", 1)
    status, _, note = rest.partition(":")
    status = status.strip()
    if status not in ("PASS", "FAIL", "NOT RUN", "BLOCKED"):
        raise ValueError(f"bad status in --extra {spec!r}")
    return {"check": name.strip(), "status": status, "target": "manual",
            "details": [note.strip() or "(manual result, no note)"]}


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render QA results as Markdown.")
    ap.add_argument("--results", required=True, help="JSONL input.")
    ap.add_argument("--out", required=True, help="Markdown output path.")
    ap.add_argument("--title", default="QA results")
    ap.add_argument("--commit", default="unknown")
    ap.add_argument("--branch", default="unknown")
    ap.add_argument("--extra", action="append", default=[],
                    help="'check=status: note' for manual gates.")
    args = ap.parse_args(argv)

    rows = load_results(args.results)
    for spec in args.extra:
        rows.append(parse_extra(spec))
    rows.sort(key=lambda r: (ORDER.get(r["status"], 9), r["check"]))

    now = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%d %H:%M UTC")
    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1

    L = []
    L.append(f"# {args.title}")
    L.append("")
    L.append(f"Date: {now}. Branch: `{args.branch}`. Commit: `{args.commit}`.")
    L.append(f"Host: `{os.uname().nodename}` "
             f"({os.uname().sysname} {os.uname().machine}).")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append("| Check | Status | Notes |")
    L.append("|---|---|---|")
    for r in rows:
        first = (r["details"][0] if r["details"] else "")
        first = first.replace("|", "\\|")[:100]
        L.append(f"| {r['check']} | {r['status']} | {first} |")
    L.append("")
    total = ", ".join(f"{k}: {counts[k]}" for k in
                      ("PASS", "FAIL", "NOT RUN", "BLOCKED") if k in counts)
    L.append(f"Totals — {total or 'no results'}.")
    L.append("")
    L.append("## Details")
    L.append("")
    for r in rows:
        L.append(f"### {r['check']} — {r['status']}")
        L.append("")
        if r.get("target"):
            L.append(f"Target: `{r['target']}`")
            L.append("")
        L.append("```")
        for d in r["details"]:
            L.append(str(d)[:500])
        L.append("```")
        L.append("")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"wrote {args.out} ({len(rows)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
