#!/usr/bin/env bash
# test-package.sh — SqueezeboxGo package-content tests (host-only).
#
# Asserts, from the repo tree alone (+ a fixture ZIP build):
#   files present, icon 240x180 RGBA + deterministic, no secrets/keys,
#   no symlinks in the FAT part, FAT-safe names, scripts bash -n +
#   repo lint gate, Jive action luac-clean, Lua harness (gating +
#   cleanup sequence + exit 42), fixture ZIP content + reproducibility,
#   SHA256SUMS verification, entry install/upgrade/idempotence drills.
# A device-ZIP build runs only when the real artifacts exist (else SKIP).
#
# Usage: bash squeezebox-go/tests/test-package.sh [--json]
# Exit: 0 PASS, 1 FAIL, 3 NOT RUN, 4 BLOCKED (repo QA contract).
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -uo pipefail

GO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if REPO="$(git -C "$GO_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
	: # repo root known
else
	REPO="$(cd "$GO_ROOT/../.." && pwd)"
fi
APPLET_DIR="$REPO/squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH"
PKGVER="$(cat "$GO_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')"

JSON=0
[ "${1:-}" = '--json' ] && JSON=1

PASS=0; FAIL=0; SKIP=0
DETAILS=()
TMP="$(mktemp -d /tmp/sbgo-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); DETAILS+=("PASS: $1"); }
fail() { FAIL=$((FAIL+1)); DETAILS+=("FAIL: $1"); }
skip() { SKIP=$((SKIP+1)); DETAILS+=("SKIP: $1"); }

need() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------- 1. files present
for f in pack.sh VERSION README.md INSTALL.md UNINSTALL.md \
		apps/SqueezeboxGo.sh runtime/launch.sh runtime/restore.sh \
		runtime/vt-reset.py runtime/fb-preset.py runtime/nslookup runtime/jive-compat/json.lua \
		icon/make-icon.py tests/test-package.sh tests/test-jive-action.lua; do
	if [ -f "$GO_ROOT/$f" ]; then ok "file present: $f"; else fail "file missing: $f"; fi
done
for f in SqueezeboxRG35XXHApplet.lua SqueezeboxRG35XXHMeta.lua strings.txt loadPriority.lua; do
	if [ -f "$APPLET_DIR/$f" ]; then ok "applet present: $f"; else fail "applet missing: $f"; fi
done
grep -q 'GO_RETURN_TO_ANBERNIC' "$APPLET_DIR/strings.txt" 2>/dev/null \
	&& ok 'strings.txt has GO_RETURN_TO_ANBERNIC' \
	|| fail 'strings.txt lacks GO_RETURN_TO_ANBERNIC'
grep -q 'SQUEEZEBOX_GO' "$APPLET_DIR/SqueezeboxRG35XXHMeta.lua" 2>/dev/null \
	&& ok 'Meta gates on SQUEEZEBOX_GO' \
	|| fail 'Meta lacks SQUEEZEBOX_GO gate'
grep -q 'setDefaultSkin("RG35XXHLandscapeSkin")' "$APPLET_DIR/SqueezeboxRG35XXHMeta.lua" 2>/dev/null \
	&& ok 'BSP default skin is Landscape (fullscreen)' \
	|| fail 'BSP default skin is not Landscape (Base falls back to upstream QVGA)'
grep -q 'EXIT_RETURN_TO_FRONTEND = 42' "$APPLET_DIR/SqueezeboxRG35XXHApplet.lua" 2>/dev/null \
	&& ok 'Applet exit code is 42' \
	|| fail 'Applet lacks EXIT_RETURN_TO_FRONTEND = 42'
grep -q 'EXIT_FRONTEND=42' "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
	&& ok 'launch.sh exit code matches (42)' \
	|| fail 'launch.sh/Applet exit code mismatch'
grep -q '"audioByDefault"\] = 1' "$APPLET_DIR/SqueezeboxRG35XXHApplet.lua" 2>/dev/null \
	&& ok 'BSP grants audioByDefault (local player layout)' \
	|| fail 'BSP lacks audioByDefault (controller layout leaks in)'
if grep -q '"touch"\] = 1' "$APPLET_DIR/SqueezeboxRG35XXHApplet.lua" 2>/dev/null; then
	fail 'BSP grants touch on button-only hardware (dead skin menu)'
else
	ok 'BSP grants no touch (single skin list)'
fi
# boot env contract (0.2.0: App Center runs HOME-less; Jive segvs on
# unset HOME and dies silently without a seeded userpath/logconf).
for marker in 'JIVE_HOME_DIR' 'SQUEEZEPLAY_HOME' 'userpath' \
		'logconf.lua' 'USEALSADEVICE' 'sysv_shim' 'vt-reset' 'fb-preset'; do
	grep -q "$marker" "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
		&& ok "launch.sh wires $marker" \
		|| fail "launch.sh lacks $marker"
done
# SQUEEZEPLAY_NOPLAYBACK is presence-tested by decode_alsa.c: exporting
# it (even =0) disables the backend fork entirely (proven live: Go 0.2.2
# ran with no jive_alsa). It must default to UNSET.
if grep -q 'SQUEEZEPLAY_NOPLAYBACK:-0' "$GO_ROOT/runtime/launch.sh" 2>/dev/null; then
	fail 'launch.sh exports NOPLAYBACK=0 by default (disables backend)'
else
	ok 'launch.sh does not default NOPLAYBACK on'
fi
grep -qF 'unset SQUEEZEPLAY_NOPLAYBACK' "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
	&& ok 'launch.sh unsets NOPLAYBACK by default' \
	|| fail 'launch.sh lacks NOPLAYBACK unset'
# json compat seed (0.2.4: applets requiring "json" died; desktop Jive
# ships cjson only). launch.sh must seed userpath/json.lua.
for marker in 'jive-compat/json.lua' 'userpath/json.lua'; do
	grep -qF "$marker" "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
		&& ok "launch.sh seeds json compat: $marker" \
		|| fail "launch.sh lacks json seed: $marker"
done
# product logconf must name the operationally critical facilities:
# unlisted categories default to OFF (even their errors vanish).
for marker in 'squeezeplay.applets' 'net.http'; do
	grep -qF "$marker" "$GO_ROOT/runtime/logconf.lua" 2>/dev/null \
		&& ok "logconf names $marker" \
		|| fail "logconf lacks $marker (blind spot)"
done
# wallpaper seed (0.2.9: fresh installs had no SetupWallpaper setting,
# stock Jive never calls setBackground, home stays black instead of the
# reference gradient). Seed file ships in payload, launch.sh plants it.
for marker in 'seed/SetupWallpaper.lua' 'settings/SetupWallpaper.lua'; do
	grep -qF "$marker" "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
		&& ok "launch.sh seeds wallpaper: $marker" \
		|| fail "launch.sh lacks wallpaper seed: $marker"
done
[ -f "$GO_ROOT/runtime/seed/SetupWallpaper.lua" ] 2>/dev/null \
	&& ok 'wallpaper seed file ships' \
	|| fail 'wallpaper seed file missing'
grep -qF 'bb_sonata.png' "$GO_ROOT/runtime/seed/SetupWallpaper.lua" 2>/dev/null \
	&& ok 'wallpaper seed names bb_sonata' \
	|| fail 'wallpaper seed lacks bb_sonata'
# tap-bounce (0.2.9: 3/3 App Center taps froze scanout on Loading;
# only a real mode change re-arms the layer, proven 2/2 remotely).
grep -qF 'fb tap-bounce' "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
	&& ok 'launch.sh tap-bounces the display mode' \
	|| fail 'launch.sh lacks tap-bounce (taps freeze on Loading)'
grep -qF '1280x1024x16' "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
	&& ok 'tap-bounce cycles through stock mode' \
	|| fail 'tap-bounce lacks stock-mode leg'
# nslookup shim (0.2.6: applets shell out to nslookup, absent on stock).
grep -qF 'PATH="$ROOT:$PATH"' "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
	&& ok 'launch.sh prepends payload root to PATH (nslookup shim)' \
	|| fail 'launch.sh lacks PATH prepend for nslookup shim'
# helpers must run with SYSTEM libs: jive/lib's ancient libexpat breaks
# system python3 (proven live: XML_SetHashSalt lookup error killed both
# python helpers). Fixed strings match the run_helper() implementation.
for marker in 'run_helper() {' 'run_helper "$ROOT/vt-reset.py"' \
		'run_helper "$ROOT/fb-preset.py"' 'fb pre-set to 640x480x32'; do
	grep -qF "$marker" "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
		&& ok "launch.sh helper sanitize: $marker" \
		|| fail "launch.sh helper not sanitized: $marker"
done
# input mapper lifecycle (0.2.2: physical controls dead without it).
for marker in 'MAPPER_BIN="$ROOT/input/evdev2jive-stock"' \
		'MAPPER_MAP="$ROOT/input/rg35xxh-stock.map"' \
		'start_mapper' 'stop_mapper' 'kill_mapper_tree'; do
	grep -qF "$marker" "$GO_ROOT/runtime/launch.sh" 2>/dev/null \
		&& ok "launch.sh mapper: $marker" \
		|| fail "launch.sh mapper lacks: $marker"
done
# mapper kills must match by /proc exe link: -x never matches the
# 17-char comm, and -f argv match suicides admin shells mentioning it.
if grep -q 'pgrep .*evdev2jive-stock\|pkill .*evdev2jive-stock' "$GO_ROOT/runtime/launch.sh" 2>/dev/null; then
	fail 'launch.sh matches mapper by name (use kill_mapper_tree exe scan)'
else
	ok 'launch.sh kills mapper by exe link only'
fi
grep -q 'vt-reset' "$GO_ROOT/runtime/restore.sh" 2>/dev/null \
	&& ok 'restore.sh resets VT' \
	|| fail 'restore.sh lacks vt-reset'
grep -qF 'unset LD_LIBRARY_PATH LD_PRELOAD' "$GO_ROOT/runtime/restore.sh" 2>/dev/null \
	&& ok 'restore.sh sanitizes loader env' \
	|| fail 'restore.sh lacks loader sanitize'

# ------------------------------------------------- 2. icon
if need python3; then
	if python3 "$GO_ROOT/icon/make-icon.py" -o "$TMP/icon-a.png" >"$TMP/icon.out" 2>&1 \
		&& python3 "$GO_ROOT/icon/make-icon.py" -o "$TMP/icon-b.png" >>"$TMP/icon.out" 2>&1; then
		if need file; then
			file "$TMP/icon-a.png" | grep -q '240 x 180' \
				&& ok 'icon file(1): 240x180' \
				|| fail "icon file(1): $(file -b "$TMP/icon-a.png")"
			file "$TMP/icon-a.png" | grep -q 'RGBA' \
				&& ok 'icon file(1): RGBA' \
				|| fail "icon file(1): $(file -b "$TMP/icon-a.png")"
		else
			skip 'file(1) missing for icon check'
		fi
		python3 - "$TMP/icon-a.png" >"$TMP/ihdr.out" 2>&1 <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'\x89PNG\r\n\x1a\n', 'bad PNG signature'
ln, typ = struct.unpack('>I4s', d[8:16])
assert typ == b'IHDR', 'first chunk not IHDR'
w, h, bd, ct, comp, filt, inter = struct.unpack('>IIBBBBB', d[16:29])
print('%d %d %d %d' % (w, h, bd, ct))
EOF
		if [ "$(cat "$TMP/ihdr.out" 2>/dev/null)" = '240 180 8 6' ]; then
			ok 'icon IHDR: 240x180 8-bit RGBA (color type 6)'
		else
			fail "icon IHDR: $(cat "$TMP/ihdr.out" 2>/dev/null || echo unreadable)"
		fi
		if cmp -s "$TMP/icon-a.png" "$TMP/icon-b.png"; then
			ok 'icon generation deterministic (rebuild-twice identical)'
		else
			fail 'icon generation NOT deterministic'
		fi
	else
		fail "make-icon.py failed: $(cat "$TMP/icon.out")"
	fi
else
	skip 'python3 missing for icon checks'
fi

# ------------------------------------------------- 3. no secrets/keys
# Shipped trees must carry no key material or credentials.
SECRET_HITS=''
SECRET_HITS="$(grep -rInE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|PRIVATE KEY BLOCK|api[_-]?key\s*[:=]|password\s*[:=]\s*[^ ]|passwd\s*[:=]' \
	"$GO_ROOT" "$APPLET_DIR" 2>/dev/null \
	| grep -v 'test-package.sh' || true)"
if [ -z "$SECRET_HITS" ]; then
	ok 'no secrets/keys in shipped trees'
else
	fail "secret-like hits: $SECRET_HITS"
fi

# ------------------------------------------------- 4. shell syntax + lint
for f in pack.sh apps/SqueezeboxGo.sh runtime/launch.sh runtime/restore.sh tests/test-package.sh; do
	if bash -n "$GO_ROOT/$f" 2>"$TMP/syn.err"; then
		ok "bash -n $f"
	else
		fail "bash -n $f: $(cat "$TMP/syn.err")"
	fi
done
if sh -n "$GO_ROOT/apps/SqueezeboxGo.sh" 2>"$TMP/syn.err"; then
	ok 'entry is POSIX sh-clean (sh -n)'
else
	fail "entry sh -n: $(cat "$TMP/syn.err")"
fi
if [ -x "$REPO/tests/run_shellcheck.sh" ]; then
	# The gate prunes '*/.muse/*' paths (agent worktrees); run it on
	# identical copies outside the worktree so the verdict is real.
	mkdir -p "$TMP/lint" && cp "$GO_ROOT/pack.sh" "$GO_ROOT/apps/SqueezeboxGo.sh" \
		"$GO_ROOT/runtime/launch.sh" "$GO_ROOT/runtime/restore.sh" \
		"$GO_ROOT/tests/test-package.sh" "$TMP/lint/"
	if bash "$REPO/tests/run_shellcheck.sh" "$TMP/lint" >"$TMP/sc.out" 2>&1; then
		if grep -q 'shellcheck not installed' "$TMP/sc.out"; then
			ok 'lint gate: bash -n fallback PASS (shellcheck absent on host)'
		else
			ok 'lint gate: shellcheck PASS'
		fi
	else
		fail "lint gate: $(grep -v '^\[shellcheck\] .*clean' "$TMP/sc.out" | head -5 | tr '\n' ';')"
	fi
else
	skip 'tests/run_shellcheck.sh missing'
fi

# ------------------------------------------------- 5. Lua syntax + harness
LUAC=''
for c in luac5.1 luac; do need "$c" && LUAC="$c" && break; done
if [ -n "$LUAC" ]; then
	for f in SqueezeboxRG35XXHApplet.lua SqueezeboxRG35XXHMeta.lua loadPriority.lua tests/test-jive-action.lua; do
		p="$APPLET_DIR/$f"; [ "$f" = 'tests/test-jive-action.lua' ] && p="$GO_ROOT/$f"
		if "$LUAC" -p "$p" 2>"$TMP/luac.err"; then
			ok "luac $f"
		else
			fail "luac $f: $(cat "$TMP/luac.err")"
		fi
	done
else
	skip 'no luac (5.1) for Lua syntax checks'
fi
if need lua5.1; then
	run_harness() { # $1=desc, rest=env assignments
		desc="$1"; shift
		if env -u SQUEEZEBOX_GO "$@" lua5.1 "$GO_ROOT/tests/test-jive-action.lua" "$APPLET_DIR" >"$TMP/harness.out" 2>&1; then
			ok "harness $desc"
		else
			fail "harness $desc: $(grep FAIL "$TMP/harness.out" | head -3 | tr '\n' ';')"
		fi
	}
	run_harness 'B/C (gate off, no bsp .so)'
	run_harness 'A (gate on)' 'SQUEEZEBOX_GO=1' 'SQUEEZEBOX_GO_RESTORE=/opt/sbgo/restore.sh'
	run_harness 'A2 (root fallback)' 'SQUEEZEBOX_GO=1' 'SQUEEZEBOX_GO_ROOT=/opt/sbgo'
	run_harness 'D (decode failed)' 'SQUEEZEBOX_GO=1' 'SQUEEZEBOX_GO_RESTORE=/opt/sbgo/restore.sh' 'SQUEEZEBOX_GO_TEST_DECODE_FAIL=1'
else
	skip 'no lua5.1 for action harness'
fi

# ------------------------------------------------- 5b. json facade
# The shipped shim must delegate decode/encode to cjson (stubbed here
# so the test is hermetic).
if need lua5.1 && [ -f "$GO_ROOT/runtime/jive-compat/json.lua" ]; then
	if lua5.1 - "$GO_ROOT/runtime/jive-compat/json.lua" >"$TMP/json.out" 2>&1 <<'EOF'
local calls = {}
package.preload["cjson"] = function()
	return {
		decode = function(s) calls[#calls + 1] = {"decode", s}; return {ok = true} end,
		encode = function(t) calls[#calls + 1] = {"encode", t}; return "{}" end,
		null = {},
	}
end
local json = dofile(arg[1])
assert(json.decode('{"a":1}').ok, "decode must delegate")
assert(json.encode({}) == "{}", "encode must delegate")
assert(calls[1][1] == "decode" and calls[2][1] == "encode", "delegate order")
assert(json.null ~= nil, "null sentinel wanted")
print("facade delegates")
EOF
	then
		grep -q 'facade delegates' "$TMP/json.out" \
			&& ok 'json facade delegates to cjson' \
			|| fail "json facade: $(cat "$TMP/json.out")"
	else
		fail "json facade: $(cat "$TMP/json.out")"
	fi
elif need lua5.1; then
	fail 'json facade missing (jive-compat/json.lua)'
else
	skip 'no lua5.1 for json facade check'
fi

# ------------------------------------------------- 5c. nslookup shim
# Must print classic nslookup shape (Name:/Address: lines) for a name
# that resolves without network (localhost), and fail loudly otherwise.
if [ -x "$GO_ROOT/runtime/nslookup" ]; then
	if "$GO_ROOT/runtime/nslookup" localhost >"$TMP/ns.out" 2>&1 \
		&& grep -q 'Address: 127.0.0.1' "$TMP/ns.out" \
		&& grep -q 'Name:' "$TMP/ns.out"; then
		ok 'nslookup shim resolves localhost in nslookup shape'
	else
		fail "nslookup shim: $(cat "$TMP/ns.out" 2>/dev/null | tr '\n' ';')"
	fi
	if "$GO_ROOT/runtime/nslookup" 'no-such-host.invalid' >"$TMP/ns2.out" 2>&1; then
		fail 'nslookup shim exits 0 for bogus host'
	else
		ok 'nslookup shim fails loudly for bogus host'
	fi
	# the shim runs under Jive's poisoned loader env (ancient libexpat
	# first); it must sanitize and still resolve.
	mkdir -p "$TMP/nspois" && printf 'poison' >"$TMP/nspois/libexpat.so.1"
	if LD_LIBRARY_PATH="$TMP/nspois${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
		LD_PRELOAD="/nonexistent-shim.so" \
		"$GO_ROOT/runtime/nslookup" localhost >"$TMP/ns3.out" 2>&1 \
		&& grep -q 'Address: 127.0.0.1' "$TMP/ns3.out"; then
		ok 'nslookup shim sanitizes loader env'
	else
		fail "nslookup shim poisoned-env: $(cat "$TMP/ns3.out" 2>/dev/null | tr '\n' ';')"
	fi
else
	fail 'nslookup shim missing or not executable'
fi

# ------------------------------------------------- 5d. fb-preset
# Pure checks only (ioctl needs hardware): compiles, --help works,
# and the explicit RGB tables pin XRGB8888 + RGB565 exactly.
if [ -f "$GO_ROOT/runtime/fb-preset.py" ]; then
	if python3 -m py_compile "$GO_ROOT/runtime/fb-preset.py" 2>/dev/null \
		&& python3 "$GO_ROOT/runtime/fb-preset.py" --help >/dev/null 2>&1; then
		ok 'fb-preset compiles, --help works'
	else
		fail 'fb-preset py_compile/--help'
	fi
	if python3 - "$GO_ROOT/runtime" >"$TMP/fb.out" 2>&1 <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import importlib.util
spec = importlib.util.spec_from_file_location(
    "fbpreset", sys.argv[1] + "/fb-preset.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
f32 = m.fields_for_bpp(32)
assert (f32["red.offset"], f32["red.length"]) == (16, 8), f32
assert (f32["green.offset"], f32["green.length"]) == (8, 8), f32
assert (f32["blue.offset"], f32["blue.length"]) == (0, 8), f32
f16 = m.fields_for_bpp(16)
assert (f16["red.offset"], f16["red.length"]) == (11, 5), f16
assert (f16["green.offset"], f16["green.length"]) == (5, 6), f16
assert (f16["blue.offset"], f16["blue.length"]) == (0, 5), f16
try:
    m.fields_for_bpp(24)
    raise SystemExit("24bpp accepted")
except ValueError:
    pass
print("fields pin XRGB8888 + RGB565")
EOF
	then
		grep -q 'fields pin' "$TMP/fb.out" \
			&& ok 'fb-preset fields pin XRGB8888 + RGB565' \
			|| fail "fb-preset fields: $(cat "$TMP/fb.out")"
	else
		fail "fb-preset fields: $(cat "$TMP/fb.out")"
	fi
else
	fail 'fb-preset.py missing for unit check'
fi

# ------------------------------------------------- 6. fixture ZIP build
ZIP1="$TMP/zip1"; ZIP2="$TMP/zip2"
if need python3 && need tar && need gzip && need sha256sum && need unzip; then
	if bash "$GO_ROOT/pack.sh" --fixture --output "$ZIP1" --epoch 1767225600 >"$TMP/pack1.out" 2>&1; then
		ok 'fixture pack.sh build exit 0'
	else
		fail "fixture pack.sh: $(tail -2 "$TMP/pack1.out" | tr '\n' ';')"
	fi
	FZIP="$ZIP1/SqueezeboxGo-$PKGVER-fixture.zip"
	if [ -f "$FZIP" ]; then
		WANT='APPS/Imgs/SqueezeboxGo.png
APPS/SqueezeboxGo.sh
APPS/SqueezeboxGo/SHA256SUMS
APPS/SqueezeboxGo/VERSION
APPS/SqueezeboxGo/payload.tar.gz'
		HAVE="$(unzip -Z1 "$FZIP" | LC_ALL=C sort)"
		if [ "$HAVE" = "$WANT" ]; then
			ok 'ZIP file list exact (5 entries)'
		else
			fail "ZIP file list: $(echo "$HAVE" | tr '\n' ',')"
		fi
		mkdir -p "$TMP/unz" && (cd "$TMP/unz" && unzip -q "$FZIP")
		if [ -z "$(find "$TMP/unz" -type l)" ]; then
			ok 'no symlinks in FAT part'
		else
			fail "symlinks in FAT part: $(find "$TMP/unz" -type l)"
		fi
		if find "$TMP/unz" | LC_ALL=C grep -q '[^ -~]'; then
			fail 'non-ASCII FAT names present'
		else
			ok 'FAT names ASCII-only'
		fi
		LOWER_DUPES="$(find "$TMP/unz" -type f | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
		if [ -z "$LOWER_DUPES" ]; then
			ok 'no FAT case-collision names'
		else
			fail "case collisions: $LOWER_DUPES"
		fi
		if (cd "$TMP/unz/APPS/SqueezeboxGo" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
			ok 'SHA256SUMS verifies payload'
		else
			fail 'SHA256SUMS mismatch'
		fi
		mkdir -p "$TMP/pay" && tar -xzf "$TMP/unz/APPS/SqueezeboxGo/payload.tar.gz" -C "$TMP/pay"
		if [ -f /usr/include/linux/vt.h ] && [ -f /usr/include/linux/kd.h ]; then
		if grep -q 'define VT_UNLOCKSWITCH 0x560C' /usr/include/linux/vt.h \
			&& grep -q 'define KDSETMODE.*0x4B3A' /usr/include/linux/kd.h \
			&& grep -q 'VT_UNLOCKSWITCH = 0x560C' "$GO_ROOT/runtime/vt-reset.py" \
			&& grep -q 'KDSETMODE = 0x4B3A' "$GO_ROOT/runtime/vt-reset.py"; then
			ok 'vt-reset ioctl constants match kernel UAPI'
		else
			fail 'vt-reset ioctl constants mismatch kernel UAPI'
		fi
	else
		skip 'kernel UAPI headers absent; ioctl constants unchecked'
	fi
	for f in MANIFEST VERSION launch.sh restore.sh vt-reset.py fb-preset.py nslookup jive/bin/jive \
				lib-fbcon/libSDL-1.2.so.0 lib-compat/sysv_shim.so \
				jive-compat/json.lua seed/SetupWallpaper.lua \
				input/evdev2jive-stock input/rg35xxh-stock.map \
				jive/share/jive/applets/SqueezeboxRG35XXH/SqueezeboxRG35XXHApplet.lua \
				jive/share/jive/applets/SqueezeboxRG35XXH/SqueezeboxRG35XXHMeta.lua \
				jive/share/jive/applets/RG35XXHBaseSkin/RG35XXHBaseSkinMeta.lua \
				jive/share/jive/applets/RG35XXHLandscapeSkin/RG35XXHLandscapeSkinMeta.lua; do
			if [ -e "$TMP/pay/$f" ]; then ok "payload has $f"; else fail "payload lacks $f"; fi
		done
		grep -q 'returnToFrontend' "$TMP/pay/jive/share/jive/applets/SqueezeboxRG35XXH/SqueezeboxRG35XXHApplet.lua" \
			&& ok 'payload applet carries returnToFrontend' \
			|| fail 'payload applet lacks returnToFrontend'
		[ "$(cat "$TMP/unz/APPS/SqueezeboxGo/VERSION")" = "$(cat "$GO_ROOT/VERSION")" ] \
			&& ok 'ZIP VERSION matches repo VERSION' \
			|| fail 'ZIP VERSION mismatch'
		# reproducibility: second build, byte-identical
		if bash "$GO_ROOT/pack.sh" --fixture --output "$ZIP2" --epoch 1767225600 >"$TMP/pack2.out" 2>&1 \
			&& cmp -s "$FZIP" "$ZIP2/SqueezeboxGo-$PKGVER-fixture.zip"; then
			ok 'fixture ZIP reproducible (rebuild-twice identical)'
		else
			fail 'fixture ZIP NOT reproducible'
		fi
	else
		fail 'fixture ZIP not produced'
	fi
else
	skip 'zip toolchain (python3/tar/gzip/sha256sum/unzip) incomplete'
fi

# ------------------------------------------------- 7. device ZIP (artifacts-gated)
JAMMY="${JAMMY_TARBALL:-/tmp/jammy-sp/squeezeplay/squeezeplay-aarch64-9.0.0.tgz}"
FBCON="${FBCON_LIB:-/tmp/sdl-fbcon/out/lib/libSDL-1.2.so.0.11.4}"
if [ -f "$JAMMY" ] && [ -f "$FBCON" ] && need python3; then
	if bash "$GO_ROOT/pack.sh" --output "$TMP/zipdev" --epoch 1767225600 >"$TMP/packdev.out" 2>&1; then
		ok 'device pack.sh build exit 0'
		DZIP="$TMP/zipdev/SqueezeboxGo-$PKGVER-stockos-rg35xxh.zip"
		mkdir -p "$TMP/unzdev" && (cd "$TMP/unzdev" && unzip -q -o "$DZIP" 'APPS/SqueezeboxGo/payload.tar.gz')
		mkdir -p "$TMP/paydev" && tar -xzf "$TMP/unzdev/APPS/SqueezeboxGo/payload.tar.gz" -C "$TMP/paydev" \
			jive/bin/jive jive/bin/jive_alsa jive/bin/lua lib-fbcon/libSDL-1.2.so.0 lib-compat/sysv_shim.so \
			jive/share/jive/applets/DesktopJive/DesktopJiveMeta.lua \
			jive/share/jive/applets/SetupAppletInstaller/SetupAppletInstallerApplet.lua \
			jive/share/jive/applets/RG35XXHLandscapeSkin/RG35XXHLandscapeSkinApplet.lua 2>/dev/null
		if need file; then
			file "$TMP/paydev/jive/bin/jive" | grep -q 'ARM aarch64' \
				&& ok 'device payload jive is aarch64' \
				|| fail "device jive: $(file -b "$TMP/paydev/jive/bin/jive" 2>/dev/null)"
		else
			skip 'file(1) missing for ELF check'
		fi
		[ -f "$TMP/paydev/lib-compat/sysv_shim.so" ] \
			&& ok 'device payload ships sysv_shim.so' \
			|| fail 'device payload lacks sysv_shim.so'
		for b in jive jive_alsa lua; do
			[ -x "$TMP/paydev/jive/bin/$b" ] \
				&& ok "device payload jive/bin/$b executable" \
				|| fail "device payload jive/bin/$b not executable"
		done
		for marker in 'machine = "rg35xxh"' 'setDeviceType("rg35xxh"' \
				'RG35XXHLandscapeSkin'; do
			grep -qF "$marker" "$TMP/paydev/jive/share/jive/applets/DesktopJive/DesktopJiveMeta.lua" 2>/dev/null \
				&& ok "device meta carries $marker" \
				|| fail "device meta lacks $marker"
		done
		grep -q 'target = target or "rg35xxh"' "$TMP/paydev/jive/share/jive/applets/SetupAppletInstaller/SetupAppletInstallerApplet.lua" 2>/dev/null \
			&& ok 'device query targets rg35xxh' \
			|| fail 'device query lacks rg35xxh target'
		grep -q 'setVideoMode(screenWidth, screenHeight, 32' "$TMP/paydev/jive/share/jive/applets/RG35XXHLandscapeSkin/RG35XXHLandscapeSkinApplet.lua" 2>/dev/null \
			&& ok 'device skin runs 32bpp' \
			|| fail 'device skin lacks 32bpp mode'
	else
		fail "device pack.sh: $(tail -2 "$TMP/packdev.out" | tr '\n' ';')"
	fi
else
	skip 'device artifacts absent (JAMMY_TARBALL/FBCON_LIB); device build not tested'
fi

# ------------------------------------------------- 8. entry install drills
# The drills exec launch.sh with the fixture jive stub (exit-42 path),
# hermetically: no cgroup escape, no frontend stop, RAM state cleaned
# afterwards. (systemd/alsa/fb drill only warns — see E2E in
# docs/test-results/go-app.md for the observed full-lifecycle runs.)
if [ -f "$ZIP1/SqueezeboxGo-$PKGVER-fixture.zip" ]; then
	mkdir -p "$TMP/roms" && (cd "$TMP/roms" && unzip -q -o "$ZIP1/SqueezeboxGo-$PKGVER-fixture.zip" 'APPS/*')
	DRILL_ENV='SQUEEZEBOX_GO_NO_ESCAPE=1 SQUEEZEBOX_GO_NO_FRONTEND_STOP=1'
	# fake-root install (entry guard requires a squeezebox-go leaf)
	# shellcheck disable=SC2086
	if env $DRILL_ENV SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go" \
			sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entry.out" 2>&1; then
		grep -q 'payload hash OK' "$TMP/entry.out" && grep -q 'installed' "$TMP/entry.out" \
			&& ok 'entry installs with hash check, launch exits 0' \
			|| fail "entry install: $(cat "$TMP/entry.out" | tr '\n' ';')"
	else
		fail "entry install rc: $(cat "$TMP/entry.out" | tr '\n' ';')"
	fi
	# re-run must skip the install (idempotent) and still exit 0
	# shellcheck disable=SC2086
	env $DRILL_ENV SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go" \
		sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entry2.out" 2>&1 || true
	grep -q 'skipping install' "$TMP/entry2.out" \
		&& ok 'entry re-run skips install (idempotent)' \
		|| fail "entry idempotence: $(cat "$TMP/entry2.out" | tr '\n' ';')"
	# the stub asserts the boot env contract (HOME, SQUEEZEPLAY_HOME,
	# seeded logconf) and exits 42; the launch log must show the clean
	# Return-to-Anbernic path, not a crash/quit.
	DRILL_LOG="$(ls -t /dev/shm/squeezebox-go/logs/launch-*.log /tmp/squeezebox-go/logs/launch-*.log 2>/dev/null | head -n 1)"
	if [ -n "$DRILL_LOG" ] && grep -q 'Return to Anbernic (clean)' "$DRILL_LOG"; then
		ok 'drill jive stub saw boot env, clean exit-42 path'
	else
		fail "drill clean-path: ${DRILL_LOG:-no launch log}"
	fi
	# App Center runs HOME-less: same drill with HOME unset must also
	# take the clean path (regression: unset HOME segv).
	# shellcheck disable=SC2086
	env -u HOME $DRILL_ENV SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go" \
		sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entry4.out" 2>&1 || true
	DRILL_LOG2="$(ls -t /dev/shm/squeezebox-go/logs/launch-*.log /tmp/squeezebox-go/logs/launch-*.log 2>/dev/null | head -n 1)"
	if [ -n "$DRILL_LOG2" ] && grep -q 'Return to Anbernic (clean)' "$DRILL_LOG2"; then
		ok 'drill clean path with HOME unset'
	else
		fail "drill HOME-less: ${DRILL_LOG2:-no launch log}"
	fi
	# poisoned loader path (bad libexpat first, mirroring jive/lib on
	# device): python helpers must still run sanitized — no loader
	# errors in the launch log, and the vt prelude must execute.
	mkdir -p "$TMP/poison" && printf 'poison' >"$TMP/poison/libexpat.so.1"
	# shellcheck disable=SC2086
	env $DRILL_ENV LD_LIBRARY_PATH="$TMP/poison${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
		SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go" \
		sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entry5.out" 2>&1 || true
	DRILL_LOG3="$(ls -t /dev/shm/squeezebox-go/logs/launch-*.log /tmp/squeezebox-go/logs/launch-*.log 2>/dev/null | head -n 1)"
	if [ -n "$DRILL_LOG3" ] && grep -q 'error while loading shared libraries\|symbol lookup error' "$DRILL_LOG3"; then
		fail 'drill poisoned path: helper hit loader error'
	elif [ -n "$DRILL_LOG3" ] && grep -q 'vt-reset output\|vt-reset rc=' "$DRILL_LOG3"; then
		ok 'drill helpers run sanitized under poisoned path'
	else
		fail "drill poisoned path: ${DRILL_LOG3:-no launch log}"
	fi
	# upgrade must preserve config/ (jive-home, pairings, seeds): plant
	# a marker, rebuild at a new version, re-run, marker must survive.
	printf 'precious' >"$TMP/squeezebox-go/config/marker.txt"
	if bash "$GO_ROOT/pack.sh" --fixture --version 9.9.9-test --output "$TMP/zipup" --epoch 1767225600 >"$TMP/packup.out" 2>&1; then
		(cd "$TMP/roms" && unzip -q -o "$TMP/zipup/SqueezeboxGo-9.9.9-test-fixture.zip" 'APPS/*')
		# shellcheck disable=SC2086
		env $DRILL_ENV SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go" \
			sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entryup.out" 2>&1 || true
		if [ "$(cat "$TMP/squeezebox-go/config/marker.txt" 2>/dev/null)" = 'precious' ] \
			&& [ "$(cat "$TMP/squeezebox-go/VERSION" 2>/dev/null)" = '9.9.9-test' ]; then
			ok 'entry upgrade preserves config/, bumps version'
		else
			fail 'entry upgrade lost config or version'
		fi
	else
		fail "upgrade fixture pack: $(tail -2 "$TMP/packup.out" | tr '\n' ';')"
	fi
	# corrupt payload must be refused (fresh root forces reinstall path)
	printf 'corrupt' >"$TMP/roms/APPS/SqueezeboxGo/payload.tar.gz"
	rm -rf "$TMP/squeezebox-go2"
	# shellcheck disable=SC2086
	if env $DRILL_ENV SQUEEZEBOX_GO_ROOT="$TMP/squeezebox-go2" \
			sh "$TMP/roms/APPS/SqueezeboxGo.sh" >"$TMP/entry3.out" 2>&1; then
		fail 'entry accepted corrupt payload'
	else
		grep -q 'hash mismatch' "$TMP/entry3.out" \
			&& ok 'entry refuses corrupt payload' \
			|| fail "entry corrupt-path: $(cat "$TMP/entry3.out" | tr '\n' ';')"
	fi
	rm -rf /dev/shm/squeezebox-go /tmp/squeezebox-go
else
	skip 'no fixture ZIP for entry drills'
fi

# ------------------------------------------------- report
if [ "$JSON" = '1' ]; then
	STATUS='PASS'; [ "$FAIL" -ne 0 ] && STATUS='FAIL'
	printf '{"check": "go-app-package", "status": "%s", "target": "", "details": [' "$STATUS"
	FIRST=1
	for d in "${DETAILS[@]}"; do
		esc=${d//\\/\\\\}; esc=${esc//\"/\\\"}
		[ "$FIRST" -eq 1 ] && FIRST=0 || printf ', '
		printf '"%s"' "$esc"
	done
	printf '], "pass": %d, "fail": %d, "skip": %d}\n' "$PASS" "$FAIL" "$SKIP"
else
	for d in "${DETAILS[@]}"; do printf '[go-app] %s\n' "$d"; done
	printf '[go-app] totals: %d pass, %d fail, %d skip\n' "$PASS" "$FAIL" "$SKIP"
	if [ "$FAIL" -ne 0 ]; then printf '[RESULT] go-app-package: FAIL\n';
	elif [ "$PASS" -eq 0 ]; then printf '[RESULT] go-app-package: NOT RUN\n';
	else printf '[RESULT] go-app-package: PASS\n'; fi
fi
[ "$FAIL" -ne 0 ] && exit 1
[ "$PASS" -eq 0 ] && exit 3
exit 0
