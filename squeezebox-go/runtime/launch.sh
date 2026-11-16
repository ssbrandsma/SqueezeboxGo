#!/usr/bin/env bash
# launch.sh — SqueezeboxGo runtime launcher (StockOS App Center).
#
# Runs on ext4 ($SQUEEZEBOX_GO_ROOT) as root. Claim display+audio,
# snapshot stock mixer/fb state, run Jive with logs to files (App Center
# scripts lose stdout), then ALWAYS restore stock state + frontend,
# however Jive exits (trap; crash-safe).
#
# Exit-code contract (see ../README.md): Jive's Return-to-Anbernic action
# exits 42 (SQUEEZEBOX_GO_EXIT_FRONTEND). 42 = clean return; anything
# else = unexpected (still restored, logged loudly). This script itself
# exits 0 once stock state is restored, 1 only if restore failed.
#
# Env knobs (all optional):
#   SQUEEZEBOX_GO_FRONTEND        frontend unit to stop (default: see resolve)
#   SQUEEZEBOX_GO_NO_FRONTEND_STOP=1  skip frontend stop/start entirely
#   SQUEEZEBOX_GO_NO_ESCAPE=1     skip systemd-run cgroup escape
#   SQUEEZEBOX_GO_JIVE_ARGS       extra args appended to the jive command
#   config/env.sh                 sourced if present (persistent overrides)
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
EXIT_FRONTEND=42

# --- RAM-backed state ----------------------------------------------------
RAM=''
for cand in /dev/shm /tmp; do
	if [ -d "$cand" ] && [ -w "$cand" ]; then RAM="$cand"; break; fi
done
[ -n "$RAM" ] || { printf '[launch] FATAL: no writable /dev/shm or /tmp\n' >&2; exit 1; }
STATE="$RAM/squeezebox-go"
mkdir -p "$STATE/logs" "$STATE/tmp" "$STATE/np" 2>/dev/null \
	|| { printf '[launch] FATAL: cannot create %s\n' "$STATE" >&2; exit 1; }

# --- persistent config ---------------------------------------------------
CONFIG="$ROOT/config"
mkdir -p "$CONFIG" 2>/dev/null || true

# --- logging: stdout is lost under App Center, so everything goes to files
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo nostamp)"
LOG="$STATE/logs/launch-$STAMP.log"
# rotate: keep the 5 newest launch logs (+ restore.log + jive.log rolling)
ls -t "$STATE"/logs/launch-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
exec >>"$LOG" 2>&1

log() { printf '[launch] %s\n' "$*"; }
log "SqueezeboxGo $VERSION starting (root=$ROOT state=$STATE)"

# Persistent operator overrides (SSH-editable, survives upgrades of /opt).
if [ -f "$CONFIG/env.sh" ]; then
	# shellcheck disable=SC1091
	. "$CONFIG/env.sh"
	log "sourced $CONFIG/env.sh"
fi

TMPDIR="$STATE/tmp"
export TMPDIR

# --- cgroup escape -------------------------------------------------------
# App Center scripts may run inside the frontend unit's cgroup; stopping
# that unit would then SIGTERM us too. Re-exec outside it when possible.
# Worst case without escape: we die on the stop, our trap restores the
# frontend, and the user lands back in App Center (safe failure).
if [ "${SQUEEZEBOX_GO_NO_ESCAPE:-0}" != '1' ] \
	&& [ "${SQUEEZEBOX_GO_ESCAPED:-0}" != '1' ] \
	&& [ -d /run/systemd/system ] \
	&& command -v systemd-run >/dev/null 2>&1; then
	# Probe first: only re-exec when a transient scope actually works.
	# (Falling back keeps us running; worst case, the frontend stop
	# SIGTERMs us and the trap restores the frontend — safe failure.)
	if systemd-run --scope --collect -p Description='SqueezeboxGo (escape probe)' \
			true >/dev/null 2>&1; then
		export SQUEEZEBOX_GO_ESCAPED=1
		log 'cgroup escape available; re-exec under systemd-run --scope'
		systemd-run --scope --collect -p Description='SqueezeboxGo' \
			"$ROOT/launch.sh" ${1+"$@"}
		rc="$?"
		log "scoped launch.sh exited $rc"
		exit "$rc"
	fi
	log 'WARN: systemd-run escape unavailable; continuing in-place'
fi

# --- frontend resolution ---------------------------------------------------
# Order: env > config/frontend-unit.txt > launcher.service default.
# The default comes from hw Phase 1 (dmenu under launcher.service); GO-HW
# recon confirms or corrects it per stock image.
UNIT="${SQUEEZEBOX_GO_FRONTEND:-}"
if [ -z "$UNIT" ] && [ -f "$CONFIG/frontend-unit.txt" ]; then
	UNIT="$(grep -v -E '^[[:space:]]*(#|$)' "$CONFIG/frontend-unit.txt" | head -n 1 | tr -d '[:space:]')"
fi
[ -n "$UNIT" ] || UNIT='launcher.service'
# Refuse infrastructure units (same policy as stock/bundle/lib-safety.sh).
case "$UNIT" in
	systemd-*|dbus*|ssh*|sshd*|NetworkManager*|systemd-networkd*|\
	systemd-logind*|systemd-udevd*|getty*|serial-getty*|*.target|\
	*[\;\|\&\$\`\(\)\<\>\*\?]*)
		log "REFUSE: will not stop infrastructure/dangerous unit: $UNIT"
		UNIT='' ;;
esac

STAMP_FILE="$STATE/frontend.stamp"
WAS_ACTIVE='unknown'

stop_frontend() {
	[ -n "$UNIT" ] || { log 'frontend handling disabled (no unit)'; return 0; }
	if [ "${SQUEEZEBOX_GO_NO_FRONTEND_STOP:-0}" = '1' ]; then
		log 'SQUEEZEBOX_GO_NO_FRONTEND_STOP=1: leaving frontend running'
		return 0
	fi
	command -v systemctl >/dev/null 2>&1 \
		|| { log 'WARN: no systemctl; cannot stop frontend (Jive may fail ALSA/fb claim)'; return 0; }
	if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
		WAS_ACTIVE='active'
	else
		WAS_ACTIVE='inactive-or-missing'
	fi
	log "frontend $UNIT pre-state: $WAS_ACTIVE"
	printf '%s\nwas_active=%s\n' "$UNIT" "$WAS_ACTIVE" >"$STAMP_FILE"
	if [ "$WAS_ACTIVE" = 'active' ]; then
		if systemctl stop "$UNIT" 2>&1; then
			log "stopped $UNIT (stop only — enables/masks untouched; reboot restores stock)"
		else
			log "WARN: systemctl stop $UNIT failed; continuing anyway"
		fi
	else
		log "not stopping: $UNIT is not active"
	fi
}

start_frontend() {
	[ -f "$STAMP_FILE" ] || { log 'no frontend stamp; nothing to restart'; return 0; }
	unit="$(head -n 1 "$STAMP_FILE" | tr -d '[:space:]')"
	was="$(grep '^was_active=' "$STAMP_FILE" | cut -d= -f2)"
	if [ "$was" != 'active' ]; then
		log "frontend $unit was not active at launch; not restarting"
		rm -f "$STAMP_FILE"
		return 0
	fi
	if [ -z "$unit" ]; then
		log 'WARN: frontend stamp empty; refusing to guess'
		return 1
	fi
	log "restarting frontend $unit"
	if systemctl start "$unit" 2>&1; then
		if systemctl is-active --quiet "$unit" 2>/dev/null; then
			log "$unit active again — stock UI should be back"
			rm -f "$STAMP_FILE"
			return 0
		fi
		log "WARN: $unit did not become active"
		return 1
	fi
	log "WARN: systemctl start $unit failed"
	return 1
}

# --- pre-launch snapshots --------------------------------------------------
snapshot() {
	if command -v alsactl >/dev/null 2>&1; then
		if alsactl -f "$STATE/mixer.pre" store 2>&1; then
			log 'mixer snapshot saved'
		else
			log 'WARN: alsactl store failed; mixer restore will be skipped'
			rm -f "$STATE/mixer.pre"
		fi
	else
		log 'WARN: alsactl missing; no mixer snapshot'
	fi
	if [ -r /sys/class/graphics/fb0/mode ]; then
		cat /sys/class/graphics/fb0/mode >"$STATE/fbmode.pre" 2>/dev/null \
			&& log "fb mode snapshot: $(cat "$STATE/fbmode.pre" 2>/dev/null)" \
			|| log 'WARN: fb mode snapshot failed'
	else
		log 'WARN: /sys/class/graphics/fb0/mode unreadable; no fb snapshot'
	fi
	if command -v fbset >/dev/null 2>&1; then
		if fbset -s >"$STATE/fbmode.fbset" 2>/dev/null; then
			log 'fbset snapshot saved'
		else
			log 'WARN: fbset -s failed'
			rm -f "$STATE/fbmode.fbset"
		fi
	else
		log 'fbset missing; sysfs snapshot only'
	fi
}

# --- cleanup (trap: runs on ANY exit path incl. SIGTERM/SIGINT/crash) -----
JIVE_PID=''
RESTORE_FAILED=0
CLEANED=0
cleanup() {
	[ "$CLEANED" = '1' ] && return 0
	CLEANED=1
	rc="${1:-0}"
	# Stop traps while cleaning up (avoid re-entry).
	trap '' TERM INT EXIT
	if [ -n "$JIVE_PID" ] && kill -0 "$JIVE_PID" 2>/dev/null; then
		log "terminating jive pid $JIVE_PID"
		kill -TERM "$JIVE_PID" 2>/dev/null || true
		for _ in 1 2 3 4 5 6 7 8 9 10; do
			kill -0 "$JIVE_PID" 2>/dev/null || break
			sleep 1
		done
		if kill -0 "$JIVE_PID" 2>/dev/null; then
			log "jive pid $JIVE_PID ignored SIGTERM; SIGKILL"
			kill -KILL "$JIVE_PID" 2>/dev/null || true
		fi
		wait "$JIVE_PID" 2>/dev/null || true
	fi
	if [ -x "$ROOT/restore.sh" ]; then
		SQUEEZEBOX_GO_STATE="$STATE" "$ROOT/restore.sh" --from-launcher \
			|| RESTORE_FAILED=1
	else
		log "WARN: $ROOT/restore.sh missing; mixer/fb NOT restored"
		RESTORE_FAILED=1
	fi
	start_frontend || RESTORE_FAILED=1
	if [ "$RESTORE_FAILED" = '1' ]; then
		log "cleanup done with FAILURES (jive rc=$rc)"
	else
		log "cleanup done (jive rc=$rc)"
	fi
}
trap 'log "got SIGTERM"; cleanup 143; exit 143' TERM
trap 'log "got SIGINT"; cleanup 130; exit 130' INT
trap 'rc=$?; cleanup "$rc"; exit "$rc"' EXIT

# --- main ------------------------------------------------------------------
JIVE_BIN="$ROOT/jive/bin/jive"
if [ ! -x "$JIVE_BIN" ]; then
	log "FATAL: jive binary missing/not executable: $JIVE_BIN (reinstall the App Center package)"
	exit 1
fi

stop_frontend
snapshot

# Jive environment (stock-verified defaults; see stock/bundle/jive-env.sh).
export SQUEEZEBOX_GO=1
export SQUEEZEBOX_GO_ROOT="$ROOT"
export SQUEEZEBOX_GO_STATE="$STATE"
export SQUEEZEBOX_GO_RESTORE="$ROOT/restore.sh"
export SQUEEZEBOX_GO_EXIT_FRONTEND="$EXIT_FRONTEND"
export NP_STATE_DIR="$STATE/np"
export JIVE_HOME_DIR="$CONFIG/jive-home"
mkdir -p "$JIVE_HOME_DIR" "$NP_STATE_DIR" 2>/dev/null || true
export LD_LIBRARY_PATH="$ROOT/lib-fbcon:$ROOT/jive/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-fbcon}"
export SDL_FBDEV="${SDL_FBDEV:-/dev/fb0}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
export USEALSA_DEVICE="${USEALSA_DEVICE:-hw:CARD=audiocodec,DEV=0}"
export SQUEEZEPLAY_NOPLAYBACK="${SQUEEZEPLAY_NOPLAYBACK:-0}"
log "env: SQUEEZEBOX_GO=1 JIVE=$JIVE_BIN"
log "env: SDL video=$SDL_VIDEODRIVER fbdev=$SDL_FBDEV audio=$SDL_AUDIODRIVER/$USEALSA_DEVICE"
log "env: LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

JIVE_LOG="$STATE/logs/jive.log"
: >"$JIVE_LOG"
log "starting jive (log: $JIVE_LOG)"
# shellcheck disable=SC2086
"$JIVE_BIN" ${SQUEEZEBOX_GO_JIVE_ARGS:-} ${1+"$@"} >>"$JIVE_LOG" 2>&1 &
JIVE_PID="$!"
wait "$JIVE_PID"
JIVE_RC="$?"
JIVE_PID=''

if [ "$JIVE_RC" = "$EXIT_FRONTEND" ]; then
	log "jive exit $JIVE_RC = Return to Anbernic (clean)"
else
	log "jive exit $JIVE_RC = UNEXPECTED (crash/quit/kill; restoring anyway)"
fi

# Normal path: run cleanup explicitly (idempotent), then report the
# RESTORE outcome — not Jive's code — to App Center.
trap - EXIT TERM INT
cleanup "$JIVE_RC"
if [ "$RESTORE_FAILED" = '1' ]; then
	log 'launch.sh exiting 1 (restore failures; see log)'
	exit 1
fi
log 'launch.sh exiting 0 (stock state restored)'
exit 0
