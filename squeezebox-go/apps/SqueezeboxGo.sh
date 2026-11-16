#!/bin/sh
# SqueezeboxGo.sh — StockOS App Center entry for SqueezeboxGo.
#
# Lives at Roms/APPS/SqueezeboxGo.sh (VFAT: plain file, no symlinks, no
# permission bits relied upon). Runs as root; stdout is lost, so every
# message also goes to the install log on ext4.
#
# Job: make sure the ext4 runtime ($SQUEEZEBOX_GO_ROOT) exists and matches
# the payload VERSION, installing/upgrading from the sibling
# Roms/APPS/SqueezeboxGo/payload.tar.gz when needed (idempotent), then
# exec the runtime launcher. Uninstall = delete the APPS files + the
# runtime dir (see UNINSTALL.md); games/saves are never touched.
#
# FAT-safe: POSIX sh only, short ASCII names, no symlinks, no perms.
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -u

APPS_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$APPS_DIR/SqueezeboxGo"
PAYLOAD="$PAYLOAD_DIR/payload.tar.gz"
WANT_VER="$(cat "$PAYLOAD_DIR/VERSION" 2>/dev/null || echo '')"

# ext4 runtime home: explicit env > /opt (preferred, always ext4) > $HOME.
if [ -n "${SQUEEZEBOX_GO_ROOT:-}" ]; then
	ROOT="$SQUEEZEBOX_GO_ROOT"
elif [ -d /opt ] && [ -w /opt ]; then
	ROOT='/opt/squeezebox-go'
else
	ROOT="${HOME:-/root}/squeezebox-go"
fi

log() {
	# Console (lost under App Center, useful over SSH) + install log.
	printf '[sbgo-entry] %s\n' "$*"
	if [ -n "${INSTALL_LOG:-}" ]; then
		printf '[sbgo-entry] %s\n' "$*" >>"$INSTALL_LOG" 2>/dev/null || true
	fi
}
fatal() { log "FATAL: $*"; exit 1; }

[ -n "$WANT_VER" ] || fatal "payload VERSION missing in $PAYLOAD_DIR (re-extract the ZIP)"
[ -f "$PAYLOAD" ] || fatal "payload missing: $PAYLOAD (re-extract the ZIP)"

HAVE_VER=''
[ -f "$ROOT/VERSION" ] && HAVE_VER="$(cat "$ROOT/VERSION" 2>/dev/null || echo '')"

# Install/upgrade when the runtime is absent or a different version.
if [ "$HAVE_VER" = "$WANT_VER" ] && [ -x "$ROOT/launch.sh" ]; then
	log "runtime $HAVE_VER present at $ROOT; skipping install"
else
	if [ -z "$HAVE_VER" ]; then
		log "installing runtime $WANT_VER to $ROOT"
	else
		log "upgrading runtime $HAVE_VER -> $WANT_VER at $ROOT"
	fi
	# Integrity first: never install a truncated/corrupt payload.
	if [ -f "$PAYLOAD_DIR/SHA256SUMS" ] && command -v sha256sum >/dev/null 2>&1; then
		(cd "$PAYLOAD_DIR" && sha256sum -c SHA256SUMS) \
			|| fatal 'payload hash mismatch; re-copy the ZIP (filesystem or transfer error)'
		log 'payload hash OK'
	else
		log 'WARN: no sha256sum or SHA256SUMS; installing unverified'
	fi
	# Refuse to touch anything that is not obviously our own runtime dir.
	case "$ROOT" in
		*/squeezebox-go) ;;
		*) fatal "refusing to install outside a squeezebox-go dir: $ROOT" ;;
	esac
	rm -rf "$ROOT"
	mkdir -p "$ROOT" || fatal "cannot create $ROOT"
	INSTALL_LOG="$ROOT/install.log"
	: >"$INSTALL_LOG" 2>/dev/null || true
	if command -v tar >/dev/null 2>&1; then
		tar -xzf "$PAYLOAD" -C "$ROOT" \
			|| fatal "payload extraction failed (disk full? corrupt file?)"
	else
		fatal 'tar missing; cannot install'
	fi
	# FAT carries no permission bits, so fix up what the payload needs.
	chmod +x "$ROOT/launch.sh" "$ROOT/restore.sh" 2>/dev/null || true
	[ -x "$ROOT/launch.sh" ] || fatal "install incomplete: $ROOT/launch.sh missing"
	INSTALLED_VER="$(cat "$ROOT/VERSION" 2>/dev/null || echo '')"
	[ "$INSTALLED_VER" = "$WANT_VER" ] \
		|| fatal "payload VERSION ($INSTALLED_VER) != $WANT_VER"
	log "runtime $INSTALLED_VER installed"
fi

INSTALL_LOG="$ROOT/install.log"
log "exec $ROOT/launch.sh"
exec "$ROOT/launch.sh" "$@"
