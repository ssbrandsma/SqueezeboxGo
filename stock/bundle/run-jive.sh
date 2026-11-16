#!/usr/bin/env bash
# run-jive.sh — stop the gaming frontend (reversibly) and launch Jive.
#
# Order of operations (safety first):
#   1. Resolve and VALIDATE the jive binary. If none exists, exit here —
#      the frontend is never stopped for a launch that cannot happen.
#   2. Resolve the frontend unit (--frontend-unit > $FRONTEND_UNIT >
#      frontend-unit.txt). Refuse to guess; refuse critical units.
#   3. Warn if the ALSA PCM is held (fuser), informational only.
#   4. `systemctl stop` the frontend (NEVER disable/mask — reboot alone
#      restores stock behavior). Record what was stopped in state/.
#   5. Exec jive with the bundle environment.
#
# When jive exits, the frontend stays stopped until you run:
#   bash restore.sh --restart-frontend
#
# Usage (on device, as root):
#   bash run-jive.sh --frontend-unit <name.service> [--yes] [--dry-run] [-- jive-args...]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$BUNDLE_ROOT/lib-safety.sh"

CLI_UNIT=''
DRY_RUN=0
JIVE_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--frontend-unit) CLI_UNIT="${2:-}"; [ -n "$CLI_UNIT" ] || fatal '--frontend-unit needs a value'; shift 2 ;;
		--frontend-unit=*) CLI_UNIT="${1#--frontend-unit=}"; [ -n "$CLI_UNIT" ] || fatal '--frontend-unit needs a value'; shift ;;
		--yes) STOCK_YES=1; export STOCK_YES; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--) shift; while [ $# -gt 0 ]; do JIVE_ARGS+=("$1"); shift; done ;;
		-h|--help)
			printf 'usage: %s --frontend-unit <name.service> [--yes] [--dry-run] [-- jive-args...]\n' "$0"
			exit 0 ;;
		*) fatal "unknown argument: $1 (jive args go after --)" ;;
	esac
done

# --- 1. jive binary (must exist BEFORE we touch the frontend) -----------
# shellcheck disable=SC1091
. "$BUNDLE_ROOT/jive-env.sh"
if [ -z "${JIVE_BIN:-}" ]; then
	for cand in "$BUNDLE_ROOT/jive/jive" '/opt/squeezeplay/bin/jive'; do
		if [ -x "$cand" ]; then JIVE_BIN="$cand"; break; fi
	done
fi
if [ -z "${JIVE_BIN:-}" ]; then
	fatal "no jive binary found. Set JIVE_BIN, drop a build at $BUNDLE_ROOT/jive/jive, or install the /opt/squeezeplay layout — then retry. Frontend untouched."
fi
[ -x "$JIVE_BIN" ] || fatal "JIVE_BIN is not executable: $JIVE_BIN"

# --- 2. frontend unit (explicit only, never guessed) --------------------
UNIT="$CLI_UNIT"
if [ -z "$UNIT" ] && [ -n "${FRONTEND_UNIT:-}" ]; then UNIT="$FRONTEND_UNIT"; fi
if [ -z "$UNIT" ] && [ -f "$BUNDLE_ROOT/frontend-unit.txt" ]; then
	UNIT="$(grep -v -E '^\s*(#|$)' "$BUNDLE_ROOT/frontend-unit.txt" | head -n 1 | tr -d '[:space:]')"
fi
if [ -z "$UNIT" ]; then
	fatal "no frontend unit given. Identify it from YOUR probe tarball (90-frontend-hunt.txt + 50-processes-services.txt), then pass --frontend-unit <name.service>. Refusing to guess."
fi
refuse_critical_unit "$UNIT"

STATE_DIR="$BUNDLE_ROOT/state"
STAMP_FILE="$STATE_DIR/stopped-unit"

plan "run jive on stock (track B3, reversible)" \
	"jive:          $JIVE_BIN ${JIVE_ARGS[*]:-(no extra args)}" \
	"frontend stop: systemctl stop $UNIT  (stop ONLY — no disable/mask; reboot restores stock)" \
	"state file:    $STAMP_FILE (restore.sh reads this to restart exactly what was stopped)" \
	"env:           SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-?} SDL_FBDEV=${SDL_FBDEV:-?} SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-?} USEALSA_DEVICE=${USEALSA_DEVICE:-?}"

# --- 3. ALSA holder warning (informational) ------------------------------
if command -v fuser >/dev/null 2>&1 && [ -d /dev/snd ]; then
	if fuser /dev/snd/* >/dev/null 2>&1; then
		note 'PCM appears HELD (fuser found a holder). Jive may fail to open ALSA;'
		note 'run this to identify the owner BEFORE forcing anything:'
		note '  fuser -v /dev/snd/*'
	else
		note 'PCM appears free (no fuser holder).'
	fi
else
	note 'fuser or /dev/snd missing; skipping PCM-holder check.'
fi

if [ "$DRY_RUN" = '1' ]; then
	note 'dry run: frontend NOT stopped, jive NOT started.'
	exit 0
fi

command -v systemctl >/dev/null 2>&1 || fatal 'systemctl not found (stock uses systemd; cannot stop frontend safely)'
confirm "Stop $UNIT and launch $JIVE_BIN?"

# --- 4. stop frontend, record state ---------------------------------------
was_active='unknown'
if systemctl is-active --quiet "$UNIT" 2>/dev/null; then was_active='active'; else was_active='inactive-or-missing'; fi
note "frontend $UNIT pre-state: $was_active"
if [ "$was_active" = 'active' ]; then
	systemctl stop "$UNIT"
	note "stopped $UNIT (stop only — unit file and enables untouched)"
else
	note "not stopping: $UNIT is not active (nothing to stop)"
fi
mkdir -p "$STATE_DIR" "$JIVE_HOME_DIR"
printf '%s\n' "$UNIT" >"$STAMP_FILE"
printf 'stopped_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" >>"$STAMP_FILE"
printf 'was_active=%s\n' "$was_active" >>"$STAMP_FILE"

# --- 5. launch ---------------------------------------------------------------
note "launching: $JIVE_BIN ${JIVE_ARGS[*]:-}"
# shellcheck disable=SC2068
exec "$JIVE_BIN" ${JIVE_ARGS[@]+"${JIVE_ARGS[@]}"}
