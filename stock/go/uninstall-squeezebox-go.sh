#!/usr/bin/env bash
# uninstall-squeezebox-go.sh — remove ONLY what install-squeezebox-go.sh added.
#
# Removes: /opt/squeezebox-go, /mnt/mmc/Roms/APPS/SqueezeboxGo.sh,
# /mnt/mmc/Roms/APPS/Imgs/SqueezeboxGo.png. Touches nothing else.
#
# Usage (on device, as root):
#   bash uninstall-squeezebox-go.sh [--yes] [--dry-run]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

GO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$GO_SRC/../bundle/lib-safety.sh"

RUNTIME='/opt/squeezebox-go'
APPS_SH='/mnt/mmc/Roms/APPS/SqueezeboxGo.sh'
APPS_PNG='/mnt/mmc/Roms/APPS/Imgs/SqueezeboxGo.png'

DRY_RUN=0
while [ $# -gt 0 ]; do
	case "$1" in
		--yes) STOCK_YES=1; export STOCK_YES; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help)
			printf 'usage: %s [--yes] [--dry-run]\n' "$0"
			exit 0 ;;
		*) fatal "unknown argument: $1 (see --help)" ;;
	esac
done

[ "$(id -u)" = '0' ] || fatal 'must run as root'

# Refuse if jive from our runtime is currently running.
if pgrep -f "$RUNTIME/app/bin/jive" >/dev/null 2>&1; then
	fatal "SqueezeboxGo is running (pgrep $RUNTIME/app/bin/jive). Exit it first."
fi

plan "uninstall SqueezeboxGo (remove added paths only)" \
	"remove: $RUNTIME" \
	"remove: $APPS_SH" \
	"remove: $APPS_PNG" \
	"everything else: untouched"

if [ "$DRY_RUN" = '1' ]; then
	note 'dry run: nothing removed.'
	exit 0
fi
confirm 'Remove the 3 SqueezeboxGo paths?'

rm -rf "$RUNTIME" "$APPS_SH" "$APPS_PNG"
for p in "$RUNTIME" "$APPS_SH" "$APPS_PNG"; do
	[ -e "$p" ] && fatal "still exists after removal: $p"
done
note 'uninstalled. Device is back to stock + whatever else was already there.'
