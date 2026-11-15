#!/bin/sh
# run_tests.sh — build evdev2jive (host) and replay the recorded scripts.
set -eu
HERE=$(dirname "$0")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CC=${CC:-gcc}
$CC -std=c99 -Wall -Wextra -O2 -o "$TMP/evdev2jive" "$HERE/../evdev2jive.c"
echo "build: OK"
pass=0; fail=0
for s in "$HERE"/t*.script; do
    base=${s%.script}
    name=$(basename "$base")
    if "$TMP/evdev2jive" --test "$HERE/../rg35xxh.map" "$s" >"$TMP/out" 2>"$TMP/err"; then
        if cmp -s "$TMP/out" "$base.expected"; then
            echo "PASS $name"; pass=$((pass+1))
        else
            echo "FAIL $name (output differs)"; diff -u "$base.expected" "$TMP/out" | head -20; fail=$((fail+1))
        fi
    else
        echo "FAIL $name (exit $?)"; head -5 "$TMP/err"; fail=$((fail+1))
    fi
done
# config-lint negatives: each must exit 2
printf 'key BTN_A KEY_X hold\n' >"$TMP/bad1.map"
printf 'key BTN_SOUTH KEY_X hold\nkey BTN_SOUTH KEY_Y hold\n' >"$TMP/bad2.map"
printf 'axis ABS_X center 2048 press 100 release 200 neg KEY_A pos KEY_B\n' >"$TMP/bad3.map"
for b in bad1 bad2 bad3; do
    if "$TMP/evdev2jive" --dump-map "$TMP/$b.map" >/dev/null 2>&1; then
        echo "FAIL $b (accepted bad map)"; fail=$((fail+1))
    else
        echo "PASS $b (rejected)"; pass=$((pass+1))
    fi
done
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
