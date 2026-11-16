#!/usr/bin/env bash
# restore.sh — return the stock system to its gaming UI (+ optional removal).
#
#   --restart-frontend   systemctl start the unit recorded in
#                        state/stopped-unit (exactly what run-jive.sh
#                        stopped — nothing else), verify it is active.
#   --remove             delete THIS bundle directory (refuses any path
#                        outside the bundle allowlist). Frontend restart
#                        is separate: pass --restart-frontend too, or reboot.
#   --all                both of the above.
#
# Nothing else is touched: no /etc, /usr, bootloader, or kernel changes
# were ever made, so there is nothing else to undo.
#
# Usage (on device, as root):
#   bash restore.sh --restart-frontend [--yes] [--dry-run]
#   bash restore.sh --remove [--yes] [--dry-run]
#   bash restore.sh --all [--yes] [--dry-run]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$BUNDLE_ROOT/lib-safety.sh"

DO_RESTART=0
DO_REMOVE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
	case "$1" in
		--restart-frontend) DO_RESTART=1; shift ;;
		--remove) DO_REMOVE=1; shift ;;
		--all) DO_RESTART=1; DO_REMOVE=1; shift ;;
		--yes) STOCK_YES=1; export STOCK_YES; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help)
			printf 'usage: %s --restart-frontend | --remove | --all [--yes] [--dry-run]\n' "$0"
			exit 0 ;;
		*) fatal "unknown argument: $1 (see --help)" ;;
	esac
done

[ "$DO_RESTART" = '1' ] || [ "$DO_REMOVE" = '1' ] \
	|| fatal 'nothing requested: pass --restart-frontend, --remove, or --all'

STAMP_FILE="$BUNDLE_ROOT/state/stopped-unit"

if [ "$DO_REMOVE" = '1' ]; then
	refuse_destructive_path "$BUNDLE_ROOT"
fi

actions=()
[ "$DO_RESTART" = '1' ] && actions+=("restart frontend from $STAMP_FILE")
[ "$DO_REMOVE" = '1' ] && actions+=("delete bundle dir $BUNDLE_ROOT")
plan "restore stock system (track B3)" "${actions[@]}"

if [ "$DRY_RUN" = '1' ]; then
	if [ "$DO_RESTART" = '1' ]; then
		if [ -f "$STAMP_FILE" ]; then
			note "dry run: would start: $(head -n 1 "$STAMP_FILE")"
		else
			note 'dry run: no state/stopped-unit (run-jive.sh never stopped anything); nothing to restart'
		fi
	fi
	[ "$DO_REMOVE" = '1' ] && note "dry run: would rm -rf $BUNDLE_ROOT"
	exit 0
fi

if [ "$DO_RESTART" = '1' ]; then
	[ -f "$STAMP_FILE" ] || fatal "no $STAMP_FILE — run-jive.sh never recorded a stop. Refusing to guess a unit; reboot restores stock anyway."
	UNIT="$(head -n 1 "$STAMP_FILE" | tr -d '[:space:]')"
	[ -n "$UNIT" ] || fatal "state file is empty: $STAMP_FILE"
	refuse_critical_unit "$UNIT"  # sanity: must still look like a plain service
	command -v systemctl >/dev/null 2>&1 || fatal 'systemctl not found'
	confirm "Start $UNIT (recorded stop from run-jive.sh)?"
	systemctl start "$UNIT"
	if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
		note "$UNIT is active again — stock gaming UI should be back"
		rm -f "$STAMP_FILE"
		note "cleared $STAMP_FILE"
	else
		fatal "$UNIT did not become active; state kept at $STAMP_FILE. Check: systemctl status $UNIT"
	fi
fi

if [ "$DO_REMOVE" = '1' ]; then
	confirm "Delete bundle directory $BUNDLE_ROOT?"
	rm -rf "$BUNDLE_ROOT"
	printf '[note] removed bundle dir. (This line prints from a deleted script — exit code is what matters.)\n'
fi
