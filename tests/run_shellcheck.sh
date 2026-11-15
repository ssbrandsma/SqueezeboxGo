#!/usr/bin/env bash
# Shell-script gate: shellcheck when available, else bash -n fallback.
# Usage: tests/run_shellcheck.sh [--json] [dir...]   (default: repo root scan)
# Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no scripts), 4 BLOCKED (no bash?).
set -u

json=0
if [ "${1:-}" = "--json" ]; then json=1; shift; fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SCAN=("$@")
[ "${#SCAN[@]}" -eq 0 ] && SCAN=("$ROOT")

mapfile -t FILES < <(find "${SCAN[@]}" -name .git -prune -o -path '*/fixtures/*' -prune -o -type f -name '*.sh' -print 2>/dev/null | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  if [ "$json" -eq 1 ]; then
    printf '{"check": "shellcheck", "status": "NOT RUN", "target": "", "details": ["no *.sh files found"]}\n'
  else
    echo "[RESULT] shellcheck: NOT RUN"
  fi
  exit 3
fi

details=()
fail=0
if command -v shellcheck >/dev/null 2>&1; then
  tool="shellcheck -S warning"
  for f in "${FILES[@]}"; do
    if out="$(shellcheck -S warning -f gcc "$f" 2>&1)"; then
      details+=("$(basename "$f"): clean")
    else
      fail=1
      while IFS= read -r line; do details+=("$line"); done <<<"$out"
    fi
  done
else
  tool="bash -n (shellcheck not installed)"
  for f in "${FILES[@]}"; do
    if bash -n "$f" 2>/tmp/sc-err.txt; then
      details+=("$(basename "$f"): syntax ok [$tool]")
    else
      fail=1
      details+=("$(basename "$f"): SYNTAX ERROR: $(cat /tmp/sc-err.txt)")
    fi
  done
  details+=("note: install shellcheck for full lint; fallback is syntax-only")
fi
details+=("checked ${#FILES[@]} script(s) with $tool")

if [ "$json" -eq 1 ]; then
  status=PASS; [ "$fail" -ne 0 ] && status=FAIL
  printf '{"check": "shellcheck", "status": "%s", "target": "", "details": [' "$status"
  first=1
  for d in "${details[@]}"; do
    esc=${d//\\/\\\\}; esc=${esc//\"/\\\"}
    [ "$first" -eq 1 ] && first=0 || printf ', '
    printf '"%s"' "$esc"
  done
  printf ']}\n'
else
  for d in "${details[@]}"; do echo "[shellcheck] $d"; done
  if [ "$fail" -ne 0 ]; then echo "[RESULT] shellcheck: FAIL"; else echo "[RESULT] shellcheck: PASS"; fi
fi
[ "$fail" -ne 0 ] && exit 1 || exit 0
