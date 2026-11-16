#!/usr/bin/env bash
# install.sh — install the stock bundle WITHOUT touching the system.
#
# Copies this bundle directory to /opt/squeezebox-stock (as root) or
# $HOME/squeezebox-stock (as a normal user). Makes NO system writes:
# no /etc files, no /usr files, no systemd units, no enables, no
# bootloader/kernel changes. Fully reversible via restore.sh --remove.
#
# Usage (on device):
#   bash install.sh [--dest DIR] [--yes] [--dry-run]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

BUNDLE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$BUNDLE_SRC/lib-safety.sh"

DEST=''
DRY_RUN=0

while [ $# -gt 0 ]; do
	case "$1" in
		--dest) DEST="${2:-}"; [ -n "$DEST" ] || fatal '--dest needs a value'; shift 2 ;;
		--dest=*) DEST="${1#--dest=}"; [ -n "$DEST" ] || fatal '--dest needs a value'; shift ;;
		--yes) STOCK_YES=1; export STOCK_YES; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help)
			printf 'usage: %s [--dest DIR] [--yes] [--dry-run]\n' "$0"
			exit 0 ;;
		*) fatal "unknown argument: $1 (see --help)" ;;
	esac
done

# Required payload present?
for f in lib-safety.sh run-jive.sh restore.sh jive-env.sh README.md; do
	[ -f "$BUNDLE_SRC/$f" ] || fatal "bundle incomplete, missing: $BUNDLE_SRC/$f"
done

# Default destination: /opt when we can create it, else $HOME.
if [ -z "$DEST" ]; then
	if [ "$(id -u)" = '0' ]; then
		DEST='/opt/squeezebox-stock'
	else
		DEST="${HOME:-/root}/squeezebox-stock"
	fi
fi
refuse_destructive_path "$DEST"

if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then
	fatal "destination exists and is not a directory: $DEST"
fi

n_files="$(find "$BUNDLE_SRC" -type f | wc -l)"
plan "install stock bundle (track B3, reversible)" \
	"source:      $BUNDLE_SRC ($n_files files)" \
	"destination: $DEST" \
	"system writes: NONE (no /etc, /usr, systemd, bootloader, or kernel changes)" \
	"undo:        bash $DEST/restore.sh --remove [--yes]"

if [ "$DRY_RUN" = '1' ]; then
	note 'dry run: no changes made. Would now copy:'
	find "$BUNDLE_SRC" -type f | sort | sed "s|^|  cp |"
	exit 0
fi

if [ -e "$DEST" ]; then
	note "destination exists; will merge/overwrite bundle files in place: $DEST"
fi
confirm "Copy bundle to $DEST?"

mkdir -p "$DEST"
cp -a "$BUNDLE_SRC/." "$DEST/"
chmod +x "$DEST/install.sh" "$DEST/run-jive.sh" "$DEST/restore.sh" 2>/dev/null || true

{
	printf 'stock bundle install receipt\n'
	printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
	printf 'source: %s\n' "$BUNDLE_SRC"
	printf 'dest: %s\n' "$DEST"
	printf 'user: %s\n' "$(id -un 2>/dev/null || echo unknown)"
	printf 'files:\n'
	(cd "$DEST" && find . -type f | sort)
} >"$DEST/install-receipt.txt"

note "installed to $DEST"
note 'next steps:'
note "  1. identify the gaming frontend unit (see README.md 'frontend unit')"
note "  2. bash $DEST/run-jive.sh --frontend-unit <name.service>   # stops frontend, starts jive"
note "  3. bash $DEST/restore.sh --restart-frontend                # back to stock gaming UI"
