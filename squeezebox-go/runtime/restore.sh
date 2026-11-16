#!/usr/bin/env bash
# restore.sh — restore stock mixer + framebuffer state (SqueezeboxGo).
#
# Called from two places (belt and braces):
#   * by Jive's Return-to-Anbernic action via $SQUEEZEBOX_GO_RESTORE
#     (`restore.sh --from-jive`), BEFORE jive exits with code 42;
#   * by launch.sh's EXIT/TERM trap AFTER jive exits (any code).
#
# Both paths are best-effort and log to $STATE/logs/restore.log; a
# failure here must never block the frontend restart.
#
# Inputs (env, all optional with fallbacks):
#   SQUEEZEBOX_GO_STATE   RAM state dir holding mixer.pre / fbmode.pre
#   SQUEEZEBOX_GO_ROOT    ext4 runtime root (for --state default)
#
# Usage: restore.sh [--from-jive|--from-launcher] [--state DIR]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -u

TAG='launcher'
STATE_DIR="${SQUEEZEBOX_GO_STATE:-}"
while [ $# -gt 0 ]; do
	case "$1" in
		--from-jive) TAG='jive'; shift ;;
		--from-launcher) TAG='launcher'; shift ;;
		--state) STATE_DIR="${2:-}"; shift 2 ;;
		--state=*) STATE_DIR="${1#--state=}"; shift ;;
		-h|--help)
			printf 'usage: %s [--from-jive|--from-launcher] [--state DIR]\n' "$0"
			exit 0 ;;
		*) printf '[restore] unknown argument: %s\n' "$1" >&2; exit 2 ;;
	esac
done

if [ -z "$STATE_DIR" ]; then
	for cand in /dev/shm/squeezebox-go /tmp/squeezebox-go; do
		if [ -d "$cand" ]; then STATE_DIR="$cand"; break; fi
	done
fi

LOG='/dev/null'
if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR/logs" ]; then
	LOG="$STATE_DIR/logs/restore.log"
fi

log() {
	# $1=level, rest=message; never fails (stdout is lost on device).
	lvl="$1"; shift
	printf '[restore:%s] %s: %s\n' "$TAG" "$lvl" "$*" >>"$LOG" 2>/dev/null || true
}

[ -n "$STATE_DIR" ] || { log WARN 'no state dir; nothing to restore from'; exit 0; }

# --- mixer ---------------------------------------------------------------
if [ -f "$STATE_DIR/mixer.pre" ]; then
	if command -v alsactl >/dev/null 2>&1; then
		if alsactl -f "$STATE_DIR/mixer.pre" restore >>"$LOG" 2>&1; then
			log INFO 'mixer restored (alsactl)'
		else
			log WARN 'alsactl restore failed (see log above)'
		fi
	else
		log WARN 'alsactl missing; cannot restore mixer.pre'
	fi
else
	log INFO 'no mixer.pre; mixer untouched'
fi

# --- framebuffer mode ----------------------------------------------------
# Stock fb0 is 1280x1024x16 but the DE scans a 640x480 layer; Jive/SDL
# may leave vinfo stuck (proven: zeroed-timings PUT -> 512x384x32, a
# valid-timings PUT restores — see docs/hardware.md). Restore the exact
# pre-launch mode. Prefer fbset (valid-timings PUT), fall back to the
# sysfs mode knob, else report and move on.
if [ -f "$STATE_DIR/fbmode.fbset" ] && command -v fbset >/dev/null 2>&1; then
	if fbset -f "$STATE_DIR/fbmode.fbset" >>"$LOG" 2>&1; then
		log INFO 'fb mode restored (fbset)'
	else
		log WARN 'fbset restore failed (see log above)'
	fi
elif [ -f "$STATE_DIR/fbmode.pre" ] && [ -w /sys/class/graphics/fb0/mode ]; then
	if cat "$STATE_DIR/fbmode.pre" >/sys/class/graphics/fb0/mode 2>>"$LOG"; then
		log INFO 'fb mode restored (sysfs)'
	else
		log WARN 'sysfs mode write failed'
	fi
else
	log INFO 'no fb restore path (no snapshot or no fbset/sysfs); fb untouched'
fi

exit 0
