#!/usr/bin/env bash
# WP1 build-and-check entrypoint (Agent 6).
# Runs every host-runnable QA gate in order, collects JSON results, and
# renders a Markdown report via scripts/gen-test-report.py.
#
# Usage: scripts/build-and-check.sh [--report PATH] [--results NAME]
#   --report PATH   write Markdown report (default: docs/test-results/wp1-qa.md)
#   --no-report     print summary only, write no file
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$ROOT"

REPORT="docs/test-results/wp1-qa.md"
while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="$2"; shift 2;;
    --no-report) REPORT=""; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RES="$TMP/results.jsonl"
: > "$RES"

run_gate() { # run_gate <label> <cmd...>
  local label="$1"; shift
  echo "--- gate: $label ---"
  set +e
  "$@" --json >>"$RES" 2>"$TMP/$label.err"
  local code=$?
  set -e
  if [ "$code" -eq 0 ]; then echo "gate $label: PASS";
  elif [ "$code" -eq 3 ]; then echo "gate $label: NOT RUN";
  elif [ "$code" -eq 4 ]; then echo "gate $label: BLOCKED";
  else echo "gate $label: FAIL (exit $code)"; fi
  [ -s "$TMP/$label.err" ] && { echo "(stderr:)"; cat "$TMP/$label.err"; }
  return 0
}

# Order: cheap static gates first, env last (needs caller to export SDE).
run_gate arch       python3 tests/check_arch.py
run_gate asound     python3 tests/check_asound.py
run_gate mapping    python3 tests/check_mapping.py
run_gate skin       python3 tests/check_skin.py
run_gate shellcheck bash tests/run_shellcheck.sh
run_gate repro-env  python3 tests/check_repro.py env

echo "--- summary ---"
python3 - "$RES" <<'EOF'
import json, sys
counts = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        counts[json.loads(line)["status"]] = counts.get(json.loads(line)["status"], 0) + 1
print("result counts:", counts or "none")
EOF

if [ -n "$REPORT" ]; then
  mkdir -p "$(dirname "$REPORT")"
  python3 scripts/gen-test-report.py --results "$RES" --out "$REPORT" \
    --title "WP1 QA results" --commit "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    --branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  echo "report written: $REPORT"
fi
