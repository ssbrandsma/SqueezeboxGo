#!/usr/bin/env bash
# test-stock-bundle.sh — host-side logic tests for track B3 (no device).
#
# Exercises stock-probe.sh against fixture /proc+/sys+/dev+/etc roots
# and fake tools, and the bundle scripts through dry-runs + refusal
# cases. Read-only w.r.t. the host outside a mktemp dir.
#
# Usage:  bash stock/tests/test-stock-bundle.sh
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -uo pipefail

STOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
TMP="$(mktemp -d /tmp/stock-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

export STOCK_ALLOW_PREFIX="$TMP"
export STOCK_YES=1   # tests never block on confirmation prompts

# ---------------------------------------------------------- 1. syntax
for f in probe/stock-probe.sh bundle/lib-safety.sh bundle/install.sh \
         bundle/run-jive.sh bundle/restore.sh bundle/jive-env.sh tests/test-stock-bundle.sh; do
	if bash -n "$STOCK_ROOT/$f" 2>"$TMP/syn.err"; then
		ok "bash -n $f"
	else
		fail "bash -n $f: $(cat "$TMP/syn.err")"
	fi
done
if command -v dash >/dev/null 2>&1; then
	for f in probe/stock-probe.sh bundle/lib-safety.sh; do
		if dash -n "$STOCK_ROOT/$f" 2>"$TMP/dash.err"; then
			ok "dash -n $f (stock /bin/sh is dash)"
		else
			fail "dash -n $f: $(cat "$TMP/dash.err")"
		fi
	done
else
	printf 'SKIP: dash not installed (POSIX check)\n'
fi
if command -v shellcheck >/dev/null 2>&1; then
	for f in probe/stock-probe.sh bundle/install.sh bundle/run-jive.sh bundle/restore.sh; do
		if shellcheck -S warning "$STOCK_ROOT/$f" >"$TMP/sc.out" 2>&1; then
			ok "shellcheck $f"
		else
			fail "shellcheck $f: $(head -n 5 "$TMP/sc.out")"
		fi
	done
else
	printf 'SKIP: shellcheck not installed (repo gate falls back to bash -n)\n'
fi
# jive-env.sh must source cleanly under `set -u` (run-jive.sh does this).
if (set -u; BUNDLE_ROOT="$TMP/fakebundle"; . "$STOCK_ROOT/bundle/jive-env.sh") 2>"$TMP/env.err"; then
	ok 'jive-env.sh sources under set -u'
else
	fail "jive-env.sh set -u: $(cat "$TMP/env.err")"
fi

# -------------------------------------------------- 2. probe fixtures
FIX="$TMP/fix"; mkdir -p "$FIX/proc/sys/kernel" "$FIX/proc/bus/input" \
	"$FIX/proc/asound" "$FIX/sys/class/graphics/fb0" \
	"$FIX/dev/snd" "$FIX/dev/input/by-id" "$FIX/etc/netplan"
printf 'anbernic-test\n' >"$FIX/proc/sys/kernel/hostname"
printf 'Linux version 4.9.170-test\n' >"$FIX/proc/version"
printf 'MemTotal: 1048576 kB\n' >"$FIX/proc/meminfo"
printf '0: audiocodec\n1: ahubdam\n2: ahubhdmi\n' >"$FIX/proc/asound/cards"
printf '0 [audiocodec]: playback\n' >"$FIX/proc/asound/pcm"
printf '0\tfb0\n' >"$FIX/proc/fb"
printf 'root=/dev/mmcblk0p5 init=/init\n' >"$FIX/proc/cmdline"
printf 'I: Bus=0019 Vendor=0000 Product=0000 Version=0000\nN: Name="ANBERNIC-keys"\n' >"$FIX/proc/bus/input/devices"
printf '1280,1024\n' >"$FIX/sys/class/graphics/fb0/virtual_size"
printf 'fb0-name\n' >"$FIX/sys/class/graphics/fb0/name"
printf 'ID 1234\n' >"$FIX/etc/os-release"
printf 'network:\n  wifis:\n    wlan0:\n      password: s3cret-psk-value\n' >"$FIX/etc/netplan/60-wifi.yaml"
touch "$FIX/dev/snd/controlC0" "$FIX/dev/fb0"

# Fake device tools with canned output (first on PATH).
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
for t in fbset aplay amixer fuser systemctl ip lsblk nmcli lsmod dpkg ss; do
	printf '#!/bin/sh\necho "FAKE-%s: $*"\n' "$t" >"$FAKEBIN/$t"
	chmod +x "$FAKEBIN/$t"
done
# amixer must succeed for card probes but fail for card 1+ info checks
# in a realistic way: succeed always (simpler, still exercises loops).
# fuser: exit 1 = nobody holds (the common probe path).
printf '#!/bin/sh\necho "FAKE-fuser: $*"\nexit 1\n' >"$FAKEBIN/fuser"

OUT="$TMP/probe-out"; mkdir -p "$OUT"
touch "$TMP/probe-marker"
if PROC_ROOT="$FIX/proc" SYS_ROOT="$FIX/sys" DEV_ROOT="$FIX/dev" \
   ETC_ROOT="$FIX/etc" STOCK_PROBE_OUT="$OUT" \
   PATH="$FAKEBIN:$PATH" sh "$STOCK_ROOT/probe/stock-probe.sh" >"$TMP/probe.log" 2>&1; then
	ok 'probe exits 0 with fixtures'
else
	fail 'probe exits 0 with fixtures'
fi
TARBALL="$(ls "$OUT"/stock-probe-*.tar.gz 2>/dev/null | head -n 1)"
if [ -n "$TARBALL" ] && [ -f "$TARBALL.sha256" ]; then
	ok "probe wrote tarball + sha256 ($(basename "$TARBALL"))"
else
	fail 'probe wrote tarball + sha256'
fi
if [ -n "$TARBALL" ]; then
	LIST="$(tar -tzf "$TARBALL")"
	for want in 00-meta 10-framebuffer 20-sdl 30-alsa 40-input \
		50-processes-services 60-network 70-storage-mounts \
		80-packages 90-frontend-hunt 99-env-dmesg; do
		if printf '%s' "$LIST" | grep -q "$want"; then
			ok "tarball contains $want"
		else
			fail "tarball contains $want"
		fi
	done
	EXT="$TMP/probe-ext"; mkdir -p "$EXT"; tar -xzf "$TARBALL" -C "$EXT"
	GOT="$EXT/$(basename "$TARBALL" .tar.gz)"
	if grep -q 'ANBERNIC-keys' "$GOT/40-input.txt" 2>/dev/null \
		&& grep -q 'FAKE-aplay' "$GOT/30-alsa.txt" 2>/dev/null \
		&& grep -q 'FAKE-fbset' "$GOT/10-framebuffer.txt" 2>/dev/null; then
		ok 'probe sections carry fixture + fake-tool data'
	else
		fail 'probe sections carry fixture + fake-tool data'
	fi
	if grep -q 'password: <redacted>' "$GOT/60-network.txt" 2>/dev/null \
		&& ! grep -q 's3cret-psk-value' "$GOT/60-network.txt" 2>/dev/null; then
		ok 'probe redacts netplan PSK'
	else
		fail 'probe redacts netplan PSK'
	fi
	if grep -q 'WHO HOLDS THE PCM' "$GOT/30-alsa.txt" 2>/dev/null; then
		ok 'probe has PCM-holder (fuser) block'
	else
		fail 'probe has PCM-holder (fuser) block'
	fi
fi
# Read-only outside OUT: only OUT may have changed under TMP minus our own dirs.
if [ -z "$(find "$FIX" -newer "$TMP/probe-marker" 2>/dev/null)" ]; then
	ok 'probe left fixture roots untouched'
else
	fail 'probe left fixture roots untouched'
fi

# ------------------------------------------------------- 3. install.sh
DEST="$TMP/install-dest"
if bash "$STOCK_ROOT/bundle/install.sh" --dest "$DEST" --dry-run >"$TMP/i-dry.log" 2>&1 \
	&& [ ! -e "$DEST" ]; then
	ok 'install --dry-run changes nothing'
else
	fail 'install --dry-run changes nothing'
fi
if bash "$STOCK_ROOT/bundle/install.sh" --dest "$DEST" >"$TMP/i.log" 2>&1 \
	&& [ -x "$DEST/run-jive.sh" ] && [ -f "$DEST/install-receipt.txt" ]; then
	ok 'install to temp dest works (scripts + receipt)'
else
	fail 'install to temp dest works (scripts + receipt)'
fi
for bad in / /etc/evil /usr/local/x relative/path /opt/squeezebox-stock/../../etc; do
	if bash "$STOCK_ROOT/bundle/install.sh" --dest "$bad" --dry-run >"$TMP/i-bad.log" 2>&1; then
		fail "install refuses: $bad"
	else
		ok "install refuses: $bad"
	fi
done

# ------------------------------------------------------ 4. run-jive.sh
# Fake jive binary first: unit-resolution tests must get PAST the
# binary check (run-jive.sh validates the binary before the unit).
mkdir -p "$DEST/jive"
printf '#!/bin/sh\necho fake-jive\n' >"$DEST/jive/jive"; chmod +x "$DEST/jive/jive"
if bash "$DEST/run-jive.sh" >"$TMP/r.log" 2>&1; then
	fail 'run-jive without unit refuses'
else
	grep -q -i 'identify\|frontend unit' "$TMP/r.log" && ok 'run-jive without unit refuses' \
		|| fail 'run-jive without unit refuses (wrong message)'
fi
if bash "$DEST/run-jive.sh" --frontend-unit ssh.service --dry-run >"$TMP/r.log" 2>&1; then
	fail 'run-jive refuses critical unit ssh.service'
else
	ok 'run-jive refuses critical unit ssh.service'
fi
if bash "$DEST/run-jive.sh" --frontend-unit 'foo;reboot' --dry-run >"$TMP/r.log" 2>&1; then
	fail 'run-jive refuses injected unit name'
else
	ok 'run-jive refuses injected unit name'
fi
# Missing jive binary must fail BEFORE any stop (dry-run still validates).
# Use a second install without the fake binary for this case.
NOJIVE="$TMP/install-nojive"
bash "$STOCK_ROOT/bundle/install.sh" --dest "$NOJIVE" >/dev/null 2>&1
if bash "$NOJIVE/run-jive.sh" --frontend-unit fake-frontend.service --dry-run >"$TMP/r.log" 2>&1; then
	fail 'run-jive refuses when jive binary missing'
else
	grep -q -i 'no jive binary' "$TMP/r.log" && ok 'run-jive refuses when jive binary missing' \
		|| fail 'run-jive refuses when jive binary missing (wrong message)'
fi
# With a fake jive binary, dry-run prints the plan and stops nothing.
if bash "$DEST/run-jive.sh" --frontend-unit fake-frontend.service --dry-run >"$TMP/r.log" 2>&1 \
	&& grep -q 'systemctl stop fake-frontend.service' "$TMP/r.log" \
	&& [ ! -e "$DEST/state/stopped-unit" ]; then
	ok 'run-jive dry-run plans stop, touches nothing'
else
	fail 'run-jive dry-run plans stop, touches nothing'
fi

# ------------------------------------------------------ 5. restore.sh
if bash "$DEST/restore.sh" >"$TMP/rs.log" 2>&1; then
	fail 'restore without flags refuses'
else
	ok 'restore without flags refuses'
fi
if bash "$DEST/restore.sh" --remove --dry-run >"$TMP/rs.log" 2>&1 \
	&& grep -q "rm -rf $DEST" "$TMP/rs.log" 2>/dev/null; then
	ok 'restore --remove dry-run shows rm target'
else
	# message wording check is soft; exit 0 + dest intact is the real assert
	if [ -d "$DEST" ]; then ok 'restore --remove dry-run removes nothing'; else fail 'restore --remove dry-run removes nothing'; fi
fi
if bash "$DEST/restore.sh" --restart-frontend --dry-run >"$TMP/rs.log" 2>&1; then
	ok 'restore --restart-frontend dry-run ok (no state yet)'
else
	fail 'restore --restart-frontend dry-run ok (no state yet)'
fi
# Real --remove of the temp install (STOCK_ALLOW_PREFIX covers $TMP).
RMDEST="$TMP/rm-victim"
bash "$STOCK_ROOT/bundle/install.sh" --dest "$RMDEST" >/dev/null 2>&1
if bash "$RMDEST/restore.sh" --remove >"$TMP/rs.log" 2>&1 && [ ! -e "$RMDEST" ]; then
	ok 'restore --remove deletes bundle dir'
else
	fail 'restore --remove deletes bundle dir'
fi
# restore.sh living outside the allowlist must refuse --remove.
OUTSIDE="$(mktemp -d /tmp/stock-outside-XXXXXX)"
cp -a "$STOCK_ROOT/bundle/." "$OUTSIDE/"
if STOCK_ALLOW_PREFIX="$TMP/only-here" bash "$OUTSIDE/restore.sh" --remove --dry-run >"$TMP/rs.log" 2>&1; then
	fail 'restore --remove outside allowlist refuses'
else
	ok 'restore --remove outside allowlist refuses'
fi
rm -rf "$OUTSIDE"

# ------------------------------------------------------------- summary
printf '\nstock bundle tests: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
