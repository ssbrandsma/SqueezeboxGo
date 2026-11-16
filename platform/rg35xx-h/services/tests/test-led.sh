#!/bin/sh
# test-led.sh — led.sh unit tests against a fake sysfs (no root, no hardware).
# TAP-ish output; exit 1 on any failure. Style follows standalone/tests/.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LED="$HERE/../led.sh"

pass=0; fail=0; n=0
ok() { n=$((n+1)); pass=$((pass+1)); echo "ok $n - $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }

[ -x "$LED" ] || { echo "missing led.sh: $LED" >&2; exit 1; }

T="$(mktemp -d /tmp/led-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/green:status"
for f in trigger brightness delay_on delay_off; do : > "$T/green:status/$f"; done
export LED_SYSFS="$T"

readf() { cat "$T/green:status/$1"; }

# 1-4: stage signatures
"$LED" stage firstboot && [ "$(readf trigger)" = "timer" ] \
  && [ "$(readf delay_on)" = "100" ] && [ "$(readf delay_off)" = "100" ] \
  && ok "firstboot blinks 100/100" || bad "firstboot signature"
"$LED" stage splash && [ "$(readf delay_on)" = "500" ] \
  && [ "$(readf delay_off)" = "500" ] \
  && ok "splash blinks 500/500" || bad "splash signature"
"$LED" stage wifi && [ "$(readf delay_on)" = "1000" ] \
  && [ "$(readf delay_off)" = "250" ] \
  && ok "wifi blinks 1000/250" || bad "wifi signature"
"$LED" stage squeezeplay && [ "$(readf trigger)" = "none" ] \
  && [ "$(readf brightness)" = "1" ] \
  && ok "squeezeplay solid" || bad "squeezeplay signature"

# 5-6: ok / fail
"$LED" ok && [ "$(readf trigger)" = "none" ] \
  && [ "$(readf brightness)" = "1" ] \
  && ok "ok is solid" || bad "ok signature"
"$LED" fail "test reason" 2>/dev/null && [ "$(readf trigger)" = "timer" ] \
  && [ "$(readf delay_on)" = "50" ] && [ "$(readf delay_off)" = "50" ] \
  && ok "fail strobes 50/50" || bad "fail signature"

# 7: usage errors exit 2
"$LED" bogus >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] && ok "bogus command exits 2" || bad "bogus command exits 2" "rc=$rc"
"$LED" stage bogus >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] && ok "bogus stage exits 2" || bad "bogus stage exits 2" "rc=$rc"

# 8: missing LED dir never blocks boot
LED_SYSFS="$T/empty" "$LED" stage splash >/dev/null 2>&1 \
  && ok "missing sysfs exits 0" || bad "missing sysfs exits 0"
LED_SYSFS="$T/empty" "$LED" fail x >/dev/null 2>&1 \
  && ok "missing sysfs fail exits 0" || bad "missing sysfs fail exits 0"

# 9: fallback name (*status* glob) works
mkdir -p "$T/other" "$T/other/panel-status"
for f in trigger brightness delay_on delay_off; do : > "$T/other/panel-status/$f"; done
LED_SYSFS="$T/other" "$LED" ok >/dev/null 2>&1 \
  && [ "$(cat "$T/other/panel-status/trigger")" = "none" ] \
  && ok "fallback *status* name works" || bad "fallback *status* name works"

echo "---"
echo "pass=$pass fail=$fail total=$n"
[ "$fail" = "0" ]
