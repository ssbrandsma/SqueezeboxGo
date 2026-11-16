#!/bin/sh
# stock-probe.sh — read-only stock-system collector (track B3).
#
# Runs ON the RG35XX H stock system (Ubuntu 22.04 Jammy, vendor 4.9.170)
# as root from the UART shell. Collects framebuffer, SDL, ALSA, input,
# process/service, network, storage and package facts into ONE directory,
# then packs it as ONE tarball for upload to the host.
#
# READ-ONLY GUARANTEE: the script only ever writes inside the output
# directory it creates under $STOCK_PROBE_OUT (default: current dir).
# It never writes to /etc, /usr, /boot, mounts, sysctls, ALSA state, or
# any device node. Every section is best-effort: a missing tool or file
# is recorded as MISSING/UNREADABLE, never fatal.
#
# No dependencies beyond stock Jammy coreutils + the probed tools
# themselves (fbset, aplay, amixer, systemctl, ip, dpkg, ...). If a
# probed tool is absent, that block says so and the script continues.
#
# Usage (on device, as root over UART):
#   sh stock-probe.sh
#   # -> ./stock-probe-<UTC-timestamp>-<host>.tar.gz (+ .sha256)
#
# Test hooks (host only, never needed on device):
#   PROC_ROOT / SYS_ROOT / DEV_ROOT / ETC_ROOT / STOCK_PROBE_OUT
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -u

PROG='stock-probe'
VERSION='1.0.0'

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
DEV_ROOT="${DEV_ROOT:-/dev}"
ETC_ROOT="${ETC_ROOT:-/etc}"
OUT_BASE="${STOCK_PROBE_OUT:-.}"
PAGER='cat'
export PAGER

# Redact wifi PSKs / passwords if they appear in netplan YAML. Never cat
# NetworkManager system-connections files (filenames only).
REDACT_EXPR='s/\([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]\|[Pp][Ss][Kk]\)\([[:space:]]*[:=][[:space:]]*\).*/\1\2<redacted>/'

log() { printf '%s\n' "$PROG: $*"; }
die() { printf '%s: ERROR: %s\n' "$PROG" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%S)"
HOST_RAW="$(cat "$PROC_ROOT/sys/kernel/hostname" 2>/dev/null || hostname 2>/dev/null || echo device)"
HOST_SAFE="$(printf '%s' "$HOST_RAW" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-32)"
[ -n "$HOST_SAFE" ] || HOST_SAFE='device'

[ -d "$OUT_BASE" ] || die "output base is not a directory: $OUT_BASE"
[ -w "$OUT_BASE" ] || die "output base is not writable: $OUT_BASE"

OUTDIR="$OUT_BASE/$PROG-$TIMESTAMP-$HOST_SAFE"
mkdir -p "$OUTDIR" || die "cannot create $OUTDIR"
log "writing to $OUTDIR"

SEC=''

# sec_begin <file> <title> — start a new section file.
sec_begin() {
	SEC="$OUTDIR/$1"
	{
		printf '# %s\n' "$2"
		printf '# %s v%s, %s, host=%s\n' "$PROG" "$VERSION" "$TIMESTAMP" "$HOST_RAW"
		printf '# uname: %s\n' "$(uname -a 2>/dev/null || echo unknown)"
	} >"$SEC"
}

# run <description> <cmd...> — append one guarded command block.
run() {
	desc="$1"; shift
	{
		printf '\n===== %s\n' "$desc"
		printf '$'
		printf ' %s' "$@"
		printf '\n'
		if have "$1"; then
			# shellcheck disable=SC2068
			"$@" 2>&1
			printf '[exit=%s]\n' "$?"
		else
			printf 'MISSING: command not found: %s\n' "$1"
		fi
	} >>"$SEC"
}

# show_file <path> [redact] — append one file's content, or the reason why not.
show_file() {
	path="$1"; redact="${2:-}"
	{
		printf '\n===== file: %s\n' "$path"
		if [ -e "$path" ]; then
			if [ -r "$path" ]; then
				if [ "$redact" = 'redact' ]; then
					sed -e "$REDACT_EXPR" "$path" 2>&1
				else
					cat "$path" 2>&1
				fi
			else
				printf 'UNREADABLE: permission denied\n'
			fi
		else
			printf 'ABSENT: no such file\n'
		fi
	} >>"$SEC"
}

# show_dir <path> — append a long listing, or the reason why not.
show_dir() {
	path="$1"
	{
		printf '\n===== dir: %s\n' "$path"
		if [ -d "$path" ]; then
			ls -la "$path" 2>&1
		else
			printf 'ABSENT: no such directory\n'
		fi
	} >>"$SEC"
}

# ---------------------------------------------------------------- 00 meta
sec_begin '00-meta.txt' 'host identity (read-only)'
show_file "$PROC_ROOT/version"
show_file "$ETC_ROOT/os-release"
run 'kernel cmdline' cat "$PROC_ROOT/cmdline"
run 'uptime' cat "$PROC_ROOT/uptime"
run 'current user' id
run 'memory' cat "$PROC_ROOT/meminfo"
run 'cpu summary' sh -c "head -30 '$PROC_ROOT/cpuinfo' 2>&1"
run 'login sessions' who
run 'local users with shells' sh -c "getent passwd 2>&1 | grep -E 'sh\$' || cat '$ETC_ROOT/passwd' 2>&1 | grep -E 'sh\$'"

# ------------------------------------------------------- 10 framebuffer
sec_begin '10-framebuffer.txt' 'framebuffer / display (read-only)'
run 'fbset current mode' fbset -s
run 'fbset info' fbset -i
run 'fbset explicit fb0' fbset -s -fb "$DEV_ROOT/fb0"
show_file "$PROC_ROOT/fb"
show_dir "$DEV_ROOT"
run 'fb device nodes' sh -c "ls -l $DEV_ROOT/fb* 2>/dev/null || ls -l $DEV_ROOT 2>&1 | grep -E ' fb[0-9]' || echo 'no /dev/fb* nodes'"
for attr in name virtual_size bits_per_pixel stride xres yres xpanstep ypanstep rotate state mode modes pan; do
	show_file "$SYS_ROOT/class/graphics/fb0/$attr"
done
show_dir "$SYS_ROOT/class/graphics"
show_dir "$DEV_ROOT/dri"
run 'dri device nodes' sh -c "ls -l $DEV_ROOT/dri 2>/dev/null || echo 'no /dev/dri (expected on stock fb stack)'"

# ---------------------------------------------------------------- 20 SDL
sec_begin '20-sdl.txt' 'SDL libraries (read-only)'
run 'ldconfig SDL entries' sh -c 'ldconfig -p 2>&1 | grep -i sdl || /sbin/ldconfig -p 2>&1 | grep -i sdl || echo "no SDL in ldconfig cache"'
run 'SDL files under lib dirs' sh -c "ls /usr/lib/*-linux-gnu*/*SDL* /usr/lib/*SDL* /usr/local/lib/*SDL* 2>&1"
run 'sdl-config if present' sh -c 'command -v sdl-config >/dev/null && { sdl-config --version; sdl-config --cflags --libs; } || command -v sdl2-config >/dev/null && { sdl2-config --version; sdl2-config --cflags --libs; } || echo "no sdl-config/sdl2-config"'
run 'SDL env currently set' sh -c 'env | grep -i -E "^SDL" || echo "no SDL_* env vars"'

# --------------------------------------------------------------- 30 ALSA
sec_begin '30-alsa.txt' 'ALSA audio (read-only)'
run 'aplay -l (cards)' aplay -l
run 'aplay -L (pcm names)' aplay -L
run 'amixer scontrols (default)' amixer scontrols
for card in 0 1 2 3 4 5 6 7; do
	if have amixer && amixer -c "$card" info >/dev/null 2>&1; then
		run "amixer -c $card scontrols" amixer -c "$card" scontrols
	fi
done
run 'amixer -c 0 contents' amixer -c 0 contents
show_file "$PROC_ROOT/asound/cards"
show_file "$PROC_ROOT/asound/devices"
show_file "$PROC_ROOT/asound/pcm"
run 'sound device nodes' sh -c "ls -l $DEV_ROOT/snd 2>/dev/null || echo 'no /dev/snd listing'"
{
	printf '\n===== fuser -v /dev/snd/* (WHO HOLDS THE PCM)\n'
	if have fuser; then
		found=0
		for node in "$DEV_ROOT"/snd/*; do
			if [ -e "$node" ]; then
				found=1
				printf '$ fuser -v %s\n' "$node"
				fuser -v "$node" 2>&1 || printf '[exit=%s — nonzero means nobody holds it]\n' "$?"
			fi
		done
		[ "$found" -eq 1 ] || printf 'no /dev/snd/* nodes to check\n'
	else
		printf 'MISSING: fuser not installed (install psmisc, or use: ls -l /proc/*/fd | grep snd)\n'
	fi
} >>"$SEC"
run 'proc-fd fallback for snd holders' sh -c "ls -l $PROC_ROOT/[0-9]*/fd 2>/dev/null | grep snd || echo 'no snd fd holders visible'"

# -------------------------------------------------------------- 40 input
sec_begin '40-input.txt' 'input devices (read-only; match by NAME)'
show_dir "$DEV_ROOT/input/by-id"
show_dir "$DEV_ROOT/input/by-path"
run 'event nodes' sh -c "ls -l $DEV_ROOT/input 2>/dev/null || echo 'no /dev/input listing'"
show_file "$PROC_ROOT/bus/input/devices"

# ------------------------------------------------- 50 procs and services
sec_begin '50-processes-services.txt' 'processes, services, modules (read-only)'
run 'process tree' ps auxf
run 'process list fallback' ps -ef
run 'all services' systemctl list-units --type=service --all --no-pager
run 'running services' systemctl list-units --type=service --state=running --no-pager
run 'failed units' systemctl list-units --failed --no-pager
run 'service unit files (autostart)' systemctl list-unit-files --type=service --no-pager
run 'default target' systemctl get-default
run 'systemd wants dirs' sh -c "ls -la '$ETC_ROOT/systemd/system/'*.wants/ 2>&1"
run 'loaded modules' cat "$PROC_ROOT/modules"
run 'lsmod (same, pretty)' lsmod

# ------------------------------------------------------------- 60 net
sec_begin '60-network.txt' 'network (read-only; secrets redacted)'
run 'ip link' ip link
run 'ip addr' ip addr
run 'ip route' ip route
run 'listening tcp sockets' sh -c 'command -v ss >/dev/null && ss -tlnp 2>&1 || netstat -tlnp 2>&1 || echo "neither ss nor netstat present"'
run 'nmcli device status' nmcli dev status
run 'nmcli connections (names only)' nmcli -t -f NAME,TYPE,DEVICE con show
run 'netplan files' sh -c "ls -la '$ETC_ROOT/netplan/' 2>&1"
for yaml in "$ETC_ROOT"/netplan/*.yaml "$ETC_ROOT"/netplan/*.yml; do
	[ -e "$yaml" ] && show_file "$yaml" redact
done
run 'NetworkManager profiles (FILENAMES ONLY, never contents)' sh -c "ls -la '$ETC_ROOT/NetworkManager/system-connections/' 2>&1 || echo 'no system-connections dir'"
run 'ssh service state' systemctl is-active ssh
run 'ssh unit file' systemctl is-enabled ssh
run 'resolv.conf' cat "$ETC_ROOT/resolv.conf"

# --------------------------------------------------- 70 storage & mounts
sec_begin '70-storage-mounts.txt' 'storage and mounts (read-only)'
run 'mount table' cat "$PROC_ROOT/mounts"
run 'mount (pretty)' mount
run 'partition list' cat "$PROC_ROOT/partitions"
run 'lsblk' lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,PARTUUID
run 'disk free' df -h
run 'boot dir (names only)' sh -c 'ls -la /boot 2>&1 | head -40'

# ------------------------------------------------------------ 80 packages
sec_begin '80-packages.txt' 'packages (read-only)'
run 'SDL/ALSA/sound/display/frontend packages' sh -c "dpkg -l 2>&1 | grep -i -E 'sdl|alsa|pulse|pipewire|bluealsa|mali|fbcon|emulation|retroarch|pegasus|kodi' || echo 'no matching packages'"
run 'full dpkg list' dpkg -l

# ------------------------------------------------------ 90 frontend hunt
sec_begin '90-frontend-hunt.txt' 'gaming-frontend identification (read-only)'
run 'frontend-like processes' sh -c "ps auxf 2>&1 | grep -i -E '[e]mulat|[r]etro|[p]egasus|[a]ttract|[k]odi|[k]ms|[w]eston|[m]utter|[g]nome-shell|Xorg|X11|[g]ame|[f]rontend|[s]dl|[f]bterm|[k]mscon|[l]ightdm|[g]dm|[s]ddm' || echo 'no obvious frontend string in ps output'"
run 'display-manager units' sh -c 'systemctl list-units --all --no-pager 2>&1 | grep -i -E "[d]isplay|[d]m\.service|[g]etty|[a]utologin" || echo "no dm/getty match"'
run 'graphical target wants' sh -c "ls -la '$ETC_ROOT/systemd/system/graphical.target.wants/' 2>&1"
run 'multi-user target wants' sh -c "ls -la '$ETC_ROOT/systemd/system/multi-user.target.wants/' 2>&1"
run 'xdg autostart' sh -c "ls -la '$ETC_ROOT/xdg/autostart/' 2>&1"
run 'share applications' sh -c 'ls /usr/share/applications/ 2>&1 | head -50'
run 'cmdline of pid 1 children consoles' sh -c "ps -o pid,ppid,tty,cmd -p 1 --ppid 1 2>&1 || ps -ef 2>&1 | head -20"

# ------------------------------------------------------------- 99 extras
sec_begin '99-env-dmesg.txt' 'env + kernel log excerpts (read-only)'
run 'environment (sorted)' sh -c 'env | sort 2>&1'
run 'dmesg display/audio/input lines' sh -c "dmesg 2>&1 | grep -i -E 'drm|panel|fb|mali|asound|alsa|axp|input|evdev|sunxi|allwinner' | head -80 || echo 'dmesg unavailable (need root?)'"
run 'dmesg tail' sh -c 'dmesg 2>&1 | tail -40 || echo "dmesg unavailable"'
run 'journal boot errors' sh -c 'journalctl -b -p err --no-pager 2>&1 | head -40 || echo "journalctl unavailable"'

# ---------------------------------------------------------- pack tarball
TARBALL="$OUT_BASE/$PROG-$TIMESTAMP-$HOST_SAFE.tar.gz"
TAR_ERR="$OUT_BASE/.tar-err-$TIMESTAMP-$HOST_SAFE.txt"
if have tar; then
	if tar -czf "$TARBALL" -C "$OUT_BASE" "$PROG-$TIMESTAMP-$HOST_SAFE" 2>"$TAR_ERR"; then
		rm -f "$TAR_ERR"
		log "tarball: $TARBALL"
		if have sha256sum; then
			sha256sum "$TARBALL" | tee "$TARBALL.sha256"
		elif have shasum; then
			shasum -a 256 "$TARBALL" | tee "$TARBALL.sha256"
		else
			log "no sha256 tool; skipping checksum"
		fi
		log "files: $(ls "$OUTDIR" | wc -l) section files"
	else
		cat "$TAR_ERR" >&2
		die "tar failed; raw dir kept at $OUTDIR"
	fi
else
	log "MISSING tar; raw dir kept at $OUTDIR (install tar or copy files individually)"
fi

log "done. Copy the tarball to your host, e.g.:"
log "  scp 'root@<device-ip>:$TARBALL' ."
log "Then attach it to docs/test-results/ per stock/README.md."
