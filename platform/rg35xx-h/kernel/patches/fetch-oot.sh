#!/usr/bin/env bash
# fetch-oot.sh — fetch REFERENCE material for porting OOT display/joypad patches.
#
# Usage:
#   fetch-oot.sh --list               print reference sources (no network)
#   fetch-oot.sh --fetch-all [--dir DIR]   shallow-fetch references to DIR
#
# This fetches GPL reference trees to study/port FROM. Nothing fetched here is
# a Squeezebox patch: ported work lands as reviewed files in kernel/patches/
# + device-tree/ per oot-patch-list.md (attribution required, no NC material).
set -euo pipefail
DEF_DIR="build/cache/oot-reference"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

log() { printf 'fetch-oot.sh: %s\n' "$*"; }
die() { printf 'fetch-oot.sh: ERROR: %s\n' "$*" >&2; exit 1; }

list_refs() {
    cat <<'EOF'
REF rocknix-dist  https://github.com/ROCKNIX/distribution.git  H700 kernel/u-boot pattern (GPL parts only; branding is CC BY-NC-SA, do not reuse)
REF sunxi-linux   https://github.com/linux-sunxi/linux-sunxi.git  historical sunxi WIP branches
REF lore-sunxi    https://lore.kernel.org/linux-arm-kernel/  upstream H616 DSI/display series (web, use b4)
NOTE muOS sunxi.dts panel timing reference: extract timing VALUES only, write own DTS (license unclear)
EOF
}

clone_ref() { # name url dir
    command -v git >/dev/null 2>&1 || die "missing git"
    local dest="$3/$1"
    if [ -d "$dest/.git" ]; then log "cached $dest"; return 0; fi
    log "cloning $1 ($2)"
    git clone --depth 1 "$2" "$dest" >&2
    log "$1 -> $dest"
}

main() {
    local cmd="" dir="$REPO_ROOT/$DEF_DIR"
    while [ $# -gt 0 ]; do
        case "$1" in
            --list) cmd=list; shift ;;
            --fetch-all) cmd=fetch; shift ;;
            --dir) dir="$2"; shift 2 ;;
            -h|--help) sed -n '2,9p' "$0"; return 0 ;;
            *) die "unknown arg: $1" ;;
        esac
    done
    [ -n "$cmd" ] || { sed -n '2,9p' "$0"; return 1; }
    if [ "$cmd" = "list" ]; then list_refs; return 0; fi
    mkdir -p "$dir"
    clone_ref rocknix-dist https://github.com/ROCKNIX/distribution.git "$dir"
    clone_ref sunxi-linux https://github.com/linux-sunxi/linux-sunxi.git "$dir"
    log "references ready in $dir (study/port only; see header)"
}

main "$@"
