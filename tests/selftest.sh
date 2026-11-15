#!/usr/bin/env bash
# Harness self-test: proves every QA check detects both good and bad input.
# Uses tests/fixtures (positive + negative cases); generates PNG fixtures
# in $TMPDIR at runtime so git stays text-only. Exit 0 = harness healthy.
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$ROOT"
FX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

expect() { # expect <want-exit> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  set +e
  "$@" >/tmp/selftest-out.txt 2>&1
  local got=$?
  set -e
  if [ "$got" -eq "$want" ]; then
    pass=$((pass+1)); echo "SELFTEST PASS: $label (exit $got)"
  else
    fail=$((fail+1)); echo "SELFTEST FAIL: $label (want $want, got $got)"
    sed 's/^/    /' /tmp/selftest-out.txt | head -8
  fi
}

# PNG fixtures (generated, never committed)
python3 - "$TMP" <<'EOF'
import struct, sys, zlib
tmp = sys.argv[1]
def png(path, w, h):
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    raw = b''.join(b'\x00' + b'\x10\x20\x30' * w for _ in range(h))
    def chunk(t, d):
        import zlib as z
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', z.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
import os
os.makedirs(f'{tmp}/skin-good', exist_ok=True); os.makedirs(f'{tmp}/skin-bad', exist_ok=True)
png(f'{tmp}/skin-good/bg.png', 640, 480)
png(f'{tmp}/skin-bad/bg.png', 641, 480)
EOF
cp "$FX/skin-good/skin.json" "$TMP/skin-good/" && cp "$FX/skin-bad/skin.json" "$TMP/skin-bad/"

echo "== asound =="
expect 0 "good conf passes"        python3 tests/check_asound.py "$FX/asound-good.conf"
expect 1 "bad conf fails"          python3 tests/check_asound.py "$FX/asound-bad.conf"

echo "== mapping =="
expect 0 "good mapping passes"     python3 tests/check_mapping.py "$FX/mapping-good.json"
expect 1 "bad mapping fails"       python3 tests/check_mapping.py "$FX/mapping-bad.json"

echo "== skin =="
expect 0 "good skin passes"        python3 tests/check_skin.py "$TMP/skin-good/skin.json"
expect 1 "bad skin fails"          python3 tests/check_skin.py "$TMP/skin-bad/skin.json"

echo "== shell =="
# NB: fixtures/ is pruned from scans, so stage copies outside it.
cp "$FX/shell-good.sh" "$TMP/good.sh"
cp "$FX/shell-bad.sh" "$TMP/bad.sh"
expect 0 "good script passes"      bash tests/run_shellcheck.sh "$TMP/good.sh"
expect 1 "bad script fails"        bash tests/run_shellcheck.sh "$TMP/bad.sh"

echo "== repro =="
expect 1 "env unset fails"         env -u SOURCE_DATE_EPOCH python3 tests/check_repro.py env
expect 0 "env set passes"          env SOURCE_DATE_EPOCH=1700000000 python3 tests/check_repro.py env
expect 1 "env garbage fails"       env SOURCE_DATE_EPOCH=tomorrow python3 tests/check_repro.py env
mkdir -p "$TMP/repro" && echo hello > "$TMP/repro/a.txt"
expect 0 "manifest writes"         python3 tests/check_repro.py manifest "$TMP/repro" -o "$TMP/m1.txt"
expect 0 "manifest writes (2nd)"   python3 tests/check_repro.py manifest "$TMP/repro" -o "$TMP/m2.txt"
expect 0 "identical compare passes" python3 tests/check_repro.py compare "$TMP/m1.txt" "$TMP/m2.txt"
echo changed > "$TMP/repro/a.txt"
expect 0 "manifest after change"   python3 tests/check_repro.py manifest "$TMP/repro" -o "$TMP/m3.txt"
expect 1 "changed compare fails"   python3 tests/check_repro.py compare "$TMP/m1.txt" "$TMP/m3.txt"

echo "== arch =="
# Host oracle: /bin/true is x86-64 with libc-only NEEDED; must PASS for
# --expect x86-64 and FAIL for --expect aarch64.
expect 0 "host binary arch ok"     python3 tests/check_arch.py --expect x86-64 --interp '' /bin/true
expect 1 "host binary not aarch64" python3 tests/check_arch.py --expect aarch64 --interp '' /bin/true
expect 3 "empty dir -> NOT RUN"    python3 tests/check_arch.py "$TMP/repro"

echo "== json mode =="
expect 0 "asound --json"           python3 tests/check_asound.py --json "$FX/asound-good.conf"
python3 tests/check_asound.py --json "$FX/asound-good.conf" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="PASS", d; print("SELFTEST PASS: json schema ok")' || fail=$((fail+1))

echo "----------------------------------------"
echo "selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
