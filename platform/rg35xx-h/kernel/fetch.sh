#!/usr/bin/env bash
# fetch.sh — fetch + verify pinned boot-chain sources (linux, u-boot, ATF).
#
# Usage:
#   fetch.sh --print-pins            print pins and exit (no network)
#   fetch.sh --check [DIR]            verify sources already in DIR
#   fetch.sh --fetch linux|u-boot|atf|all [--dir DIR] [--method tarball|git]
#
# Defaults: DIR=<repo>/build/cache/upstream (gitignored). Linux prefers the
# kernel.org tarball (published sha256); u-boot/ATF prefer a shallow git
# clone at the tag with a commit-SHA check (GitHub tarball hashes are not
# guaranteed stable, so they are a sanity check only).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/pins.env"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
DEF_DIR="$REPO_ROOT/build/cache/upstream"

log() { printf 'fetch.sh: %s\n' "$*"; }
die() { printf 'fetch.sh: ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

print_pins() {
    cat <<EOF
linux  $LINUX_TAG $LINUX_SHA
  tarball $LINUX_TARBALL
  sha256  $LINUX_TARBALL_SHA256
u-boot $UBOOT_TAG $UBOOT_SHA (tag $UBOOT_TAG_SHA)
  repo    $UBOOT_REPO defconfig $UBOOT_DEFCONFIG
atf    $ATF_TAG $ATF_SHA (tag $ATF_TAG_SHA)
  repo    $ATF_REPO plat $ATF_PLAT
EOF
}

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

fetch_tarball() { # url sha256 dest
    local url="$1" want="$2" dest="$3" got
    need curl
    if [ -f "$dest" ]; then
        got="$(sha256_file "$dest")"
        if [ "$got" = "$want" ]; then log "cached $dest OK"; return 0; fi
        log "cached $dest hash mismatch, re-downloading"
        rm -f "$dest"
    fi
    log "downloading $url"
    curl -fsSL --retry 3 -o "$dest" "$url"
    got="$(sha256_file "$dest")"
    [ "$got" = "$want" ] || die "$dest sha256 mismatch: got $got want $want"
    log "$dest OK ($got)"
}

fetch_git() { # repo tag sha dest
    local repo="$1" tag="$2" want="$3" dest="$4" got
    need git
    if [ -d "$dest/.git" ]; then
        got="$(git -C "$dest" rev-parse HEAD)"
        if [ "$got" = "$want" ]; then log "cached $dest OK ($got)"; return 0; fi
        log "cached $dest is $got, want $want; re-cloning"
        rm -rf "$dest"
    fi
    log "cloning $repo @ $tag"
    git clone --depth 1 --branch "$tag" "$repo" "$dest" >&2
    got="$(git -C "$dest" rev-parse HEAD)"
    [ "$got" = "$want" ] || die "$dest HEAD $got != pinned $want"
    log "$dest OK ($got)"
}

fetch_linux() { # dir method
    local dir="$1" method="$2"
    local dest="$dir/linux-$LINUX_VERSION"
    if [ "$method" = "git" ]; then
        fetch_git "$LINUX_REPO" "$LINUX_TAG" "$LINUX_SHA" "$dest"
    else
        local tb="$dir/linux-$LINUX_VERSION.tar.xz"
        fetch_tarball "$LINUX_TARBALL" "$LINUX_TARBALL_SHA256" "$tb"
        if [ ! -d "$dest" ]; then
            log "extracting $tb"
            tar -xJf "$tb" -C "$dir"
            mv "$dir/linux-$LINUX_VERSION" "$dest.tmp" 2>/dev/null || true
            # kernel.org tarballs extract to linux-<ver> already; normalize:
            if [ -d "$dest.tmp" ]; then mv "$dest.tmp" "$dest"; fi
        fi
        [ -f "$dest/Makefile" ] && [ -d "$dest/arch/arm64/boot/dts/allwinner" ] \
            || die "$dest extraction incomplete"
        log "$dest ready"
    fi
    # Pin evidence: the RG35XX H include chain must exist in-tree.
    for f in sun50i-h700-anbernic-rg35xx-h.dts \
             sun50i-h700-anbernic-rg35xx-plus.dts \
             sun50i-h700-anbernic-rg35xx-2024.dts; do
        [ -f "$dest/arch/arm64/boot/dts/allwinner/$f" ] \
            || die "missing in-tree DTS $f at $LINUX_TAG"
    done
    log "in-tree RG35XX DTS chain present"
}

fetch_uboot() { # dir method
    local dir="$1" method="$2"
    local dest="$dir/u-boot-$UBOOT_VERSION"
    if [ "$method" = "tarball" ]; then
        local tb="$dir/u-boot-$UBOOT_VERSION.tar.gz"
        fetch_tarball "$UBOOT_REPO/archive/refs/tags/$UBOOT_TAG.tar.gz" \
            "$UBOOT_TARBALL_SHA256" "$tb"
        [ -d "$dest" ] || { mkdir -p "$dest"; tar -xzf "$tb" -C "$dest" --strip-components=1; }
    else
        fetch_git "$UBOOT_REPO" "$UBOOT_TAG" "$UBOOT_SHA" "$dest"
    fi
    [ -f "$dest/configs/$UBOOT_DEFCONFIG" ] \
        || die "missing defconfig $UBOOT_DEFCONFIG at $UBOOT_TAG"
    log "$dest ready ($UBOOT_DEFCONFIG present)"
}

fetch_atf() { # dir method
    local dir="$1" method="$2"
    local dest="$dir/atf-$ATF_VERSION"
    if [ "$method" = "tarball" ]; then
        local tb="$dir/atf-$ATF_VERSION.tar.gz"
        fetch_tarball "$ATF_REPO/archive/refs/tags/$ATF_TAG.tar.gz" \
            "$ATF_TARBALL_SHA256" "$tb"
        [ -d "$dest" ] || { mkdir -p "$dest"; tar -xzf "$tb" -C "$dest" --strip-components=1; }
    else
        fetch_git "$ATF_REPO" "$ATF_TAG" "$ATF_SHA" "$dest"
    fi
    [ -d "$dest/plat/allwinner" ] || die "missing plat/allwinner at $ATF_TAG"
    log "$dest ready"
}

check_dir() { # dir
    local dir="$1" fail=0
    for spec in "linux-$LINUX_VERSION" "u-boot-$UBOOT_VERSION" "atf-$ATF_VERSION"; do
        if [ -d "$dir/$spec" ]; then log "present: $dir/$spec";
        else log "MISSING: $dir/$spec"; fail=1; fi
    done
    return "$fail"
}

usage() { sed -n '2,12p' "$0"; }

main() {
    local cmd="" target="" dir="$DEF_DIR" method=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --print-pins) print_pins; return 0 ;;
            --check) cmd=check; shift; [ $# -gt 0 ] && [ "${1#--}" = "$1" ] && { dir="$1"; shift; };;
            --fetch) cmd=fetch; target="${2:-}"; shift 2 || die "usage: $0 --fetch <target>";;
            --dir) dir="$2"; shift 2 ;;
            --method) method="$2"; shift 2 ;;
            -h|--help) usage; return 0 ;;
            *) die "unknown arg: $1 (see --help)" ;;
        esac
    done
    [ -n "$cmd" ] || { usage; return 1; }
    mkdir -p "$dir"
    if [ "$cmd" = "check" ]; then check_dir "$dir"; return "$?"; fi
    case "$target" in
        linux)  fetch_linux "$dir" "${method:-tarball}" ;;
        u-boot) fetch_uboot "$dir" "${method:-git}" ;;
        atf)    fetch_atf  "$dir" "${method:-git}" ;;
        all)    fetch_linux "$dir" "${method:-tarball}"
                fetch_uboot "$dir" git
                fetch_atf  "$dir" git ;;
        *) die "unknown target: $target (linux|u-boot|atf|all)" ;;
    esac
    log "done: $target -> $dir"
}

main "$@"
