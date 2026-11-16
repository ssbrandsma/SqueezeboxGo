#!/usr/bin/env bash
# stage-userland.sh — Debian base userland (debootstrap minbase) into staging.
#
# Usage:
#   stage-userland.sh --staging DIR [--suite SUITE] [--arch ARCH]
#       [--userland auto|debootstrap|container] [--mirror URL]
#       [--components LIST] [--include FILE] [--keyring FILE] [--cache DIR]
#       [--epoch EPOCH] [--force]
#
# Pipeline position: runs FIRST, before mkrootfs.sh (which layers the
# Squeezebox tree on top idempotently) and stage-payload.sh.
#
# Default (--userland auto): real `debootstrap --foreign --variant=minbase`
# under fakeroot (fully unprivileged: no root, no loop mounts, no binfmt),
# then a ROOTLESS second stage in this script:
#   * unpack every retained .deb (data + control files),
#   * synthesize /var/lib/dpkg/{status,info/*.list} as "unpacked",
#   * create /etc/{passwd,group,shadow,gshadow} from base-passwd masters
#     (locked '*', no default passwords),
#   * drop the fake /dev nodes (devtmpfs at boot), the .deb cache, and the
#     /debootstrap helper dir (after harvesting the manifest data),
#   * extend sources.list with the extra components + updates + security.
# Package *configuration* (postinst) cannot run here (arm64 binaries need a
# native CPU or binfmt, both absent in this sandbox) — it runs natively at
# first boot via squeezebox-firstboot.service (`dpkg --configure -a`), before
# ssh/wifi/squeezeplay start. See platform/rg35xx-h/services/firstboot.sh.
#
# --userland container: prints the exact privileged docker command that
# produces a natively-configured tree instead (for hosts WITH docker) and
# touches nothing. This is the documented fallback hook.
#
# Suite default is trixie, NOT bookworm: the shipped squeezeplay payload
# requires GLIBC_2.38 (__isoc23_*; measured, see docs/test-results/wp2u-image.md),
# which bookworm's libc6 2.36 does not provide. --suite bookworm still works
# (to reproduce that failure) but the image's jive cannot run on it.
# Proposed ADR-0004 amendment is recorded in the evidence doc.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf 'stage-userland.sh: %s\n' "$*"; }
die() { printf 'stage-userland.sh: ERROR: %s\n' "$*" >&2; exit 1; }

STAGING="" SUITE="trixie" ARCH="arm64" MODE="auto"
MIRROR="http://deb.debian.org/debian"
COMPONENTS="main,non-free-firmware"
INCLUDE="$HERE/userland-include.txt"
KEYRING="" CACHE="" FORCE=0 VERIFY="auto"
EPOCH="${SOURCE_DATE_EPOCH:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --staging) STAGING="$2"; shift 2 ;;
        --suite) SUITE="$2"; shift 2 ;;
        --arch) ARCH="$2"; shift 2 ;;
        --userland) MODE="$2"; shift 2 ;;
        --mirror) MIRROR="$2"; shift 2 ;;
        --components) COMPONENTS="$2"; shift 2 ;;
        --include) INCLUDE="$2"; shift 2 ;;
        --keyring) KEYRING="$2"; shift 2 ;;
        --cache) CACHE="$2"; shift 2 ;;
        --verify) VERIFY="$2"; shift 2 ;;
        --epoch) EPOCH="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
case "$MODE" in auto|debootstrap|container) ;; *) die "bad --userland $MODE" ;; esac
case "$VERIFY" in auto|yes|no) ;; *) die "bad --verify $VERIFY" ;; esac

container_cmd() {
    # Exact privileged recipe for hosts with docker: native second stage
    # inside the container (binfmt via the host or qemu-user-static).
    local inc
    inc="$(grep -vE '^\s*(#|$)' "$INCLUDE" | paste -sd, -)"
    cat <<EOF
docker run --rm --privileged -v "\$PWD:/work" -w /work debian:trixie-slim bash -c '
set -euo pipefail
apt-get update && apt-get install -y --no-install-recommends debootstrap qemu-user-static
debootstrap --arch=$ARCH --variant=minbase --components=$COMPONENTS \\
    --include=$inc $SUITE /work/build/cache/rootfs $MIRROR'
# Then continue unprivileged on the host:
#   platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs --with-services --with-config
#   build/image/stage-payload.sh --staging build/cache/rootfs [...]
EOF
}

if [ "$MODE" = "container" ]; then
    [ -f "$INCLUDE" ] || die "missing include list $INCLUDE"
    container_cmd
    exit 0
fi

[ -n "$STAGING" ] || die "need --staging DIR"
# Absolutize: the provenance step redirects into $PROV from inside a
# subshell that cd's elsewhere, and debootstrap demands an absolute
# --cache-dir; relative paths break both (seen in the 0.3.0 rebuild).
STAGING="$(realpath -m "$STAGING")"
[ -n "$CACHE" ] && CACHE="$(realpath -m "$CACHE")"
[ -f "$INCLUDE" ] || die "missing include list $INCLUDE"
command -v fakeroot >/dev/null 2>&1 || die "need fakeroot"
command -v dpkg-deb >/dev/null 2>&1 || die "need dpkg-deb"
command -v wget >/dev/null 2>&1 || die "need wget (debootstrap's fetcher)"
command -v python3 >/dev/null 2>&1 || die "need python3"
if command -v debootstrap >/dev/null 2>&1; then
    DEBOOTSTRAP=debootstrap
elif [ -n "${DEBOOTSTRAP_DIR:-}" ] && [ -x "$DEBOOTSTRAP_DIR/../sbin/debootstrap" ]; then
    DEBOOTSTRAP="$DEBOOTSTRAP_DIR/../sbin/debootstrap"
else
    log "debootstrap not found; the container hook below is the fallback:"
    container_cmd
    die "need debootstrap (or use --userland container on a docker host)"
fi

if [ -e "$STAGING/sbin/init" ] || [ -e "$STAGING/usr/lib/systemd/systemd" ] \
        || [ -e "$STAGING/debootstrap/debootstrap.log" ]; then
    [ "$FORCE" = 1 ] || die "$STAGING already holds a userland (rm -rf it or pass --force)"
fi
mkdir -p "$STAGING"

INCLUDE_CSV="$(grep -vE '^\s*(#|$)' "$INCLUDE" | sed 's/[[:space:]]//g' | paste -sd, -)"
[ -n "$INCLUDE_CSV" ] || die "empty include list $INCLUDE"
log "suite=$SUITE arch=$ARCH components=$COMPONENTS include=[$INCLUDE_CSV]"

# 1. Keyring: prefer verifying Release signatures. The host keyring may lack
# the target suite's keys (e.g. noble host vs trixie), so fetch the
# target suite's own debian-archive-keyring deb when needed.
VERIFY_STATE="skipped(no-keyring)"
keyring_for_suite() { # prints a usable keyring path or nothing
    [ -n "$KEYRING" ] && [ -f "$KEYRING" ] && { echo "$KEYRING"; return; }
    local sys=/usr/share/keyrings/debian-archive-keyring.gpg
    # The sys keyring is only useful if it carries the suite's release key.
    if [ -f "$sys" ] && command -v gpg >/dev/null 2>&1; then
        # Heuristic: trixie+ keys live in keyrings shipped after 2025.
        if [ "$SUITE" != "trixie" ] && [ "$SUITE" != "forky" ] && [ "$SUITE" != "sid" ]; then
            echo "$sys"; return
        fi
    elif [ -f "$sys" ] && { [ "$SUITE" = "bookworm" ] || [ "$SUITE" = "bullseye" ]; }; then
        echo "$sys"; return
    fi
    # Fetch the suite's own keyring deb (filename from its Packages index).
    local tmp idx fn deb
    tmp="$(mktemp -d)" || return
    idx="$tmp/Packages.gz"
    if wget -q -O "$idx" "$MIRROR/dists/$SUITE/main/binary-$ARCH/Packages.gz" 2>/dev/null; then
        fn="$(zcat "$idx" | awk '/^Package: debian-archive-keyring$/{f=1} f&&/^Filename: /{print $2; exit}')"
        if [ -n "$fn" ]; then
            deb="$tmp/keyring.deb"
            if wget -q -O "$deb" "$MIRROR/$fn" 2>/dev/null; then
                dpkg-deb -x "$deb" "$tmp/k" 2>/dev/null
                local gpgfile="$tmp/k/usr/share/keyrings/debian-archive-keyring.gpg"
                if [ -f "$gpgfile" ]; then
                    # Persist next to the staging dir (tmp vanishes on exit).
                    mkdir -p "$STAGING/../.userland-keyring"
                    cp "$gpgfile" "$STAGING/../.userland-keyring/debian-archive-$SUITE-keyring.gpg"
                    rm -rf "$tmp"
                    echo "$STAGING/../.userland-keyring/debian-archive-$SUITE-keyring.gpg"
                    return
                fi
            fi
        fi
    fi
    rm -rf "$tmp"
}
if [ "$VERIFY" != "no" ]; then
    if KR="$(keyring_for_suite)" && [ -n "$KR" ]; then
        KEYRING="$KR"; VERIFY_STATE="ok(keyring=$KR)"
        log "Release verification: $KEYRING"
    elif [ "$VERIFY" = "yes" ]; then
        die "no usable keyring for $SUITE (refusing unverified download)"
    else
        log "WARNING: no usable keyring for $SUITE; continuing UNVERIFIED (recorded in manifest)"
    fi
fi

# 2. Real debootstrap first stage (foreign: download + extract required set).
DB_ARGS=(--foreign --arch="$ARCH" --variant=minbase --components="$COMPONENTS"
    --include="$INCLUDE_CSV" --verbose)
if [ -n "$KEYRING" ]; then DB_ARGS+=(--keyring="$KEYRING"); else DB_ARGS+=(--no-check-gpg); fi
[ -n "$CACHE" ] && { mkdir -p "$CACHE"; DB_ARGS+=(--cache-dir="$CACHE"); }
log "running: fakeroot $DEBOOTSTRAP ${DB_ARGS[*]} $SUITE $STAGING $MIRROR"
# shellcheck disable=SC2068
fakeroot "$DEBOOTSTRAP" ${DB_ARGS[@]} "$SUITE" "$STAGING" "$MIRROR"
log "debootstrap first stage done"

# 3. Rootless second stage: unpack every retained .deb (data + control),
# synthesize dpkg status/info as "unpacked".
ARCHIVES="$STAGING/var/cache/apt/archives"
[ -d "$ARCHIVES" ] || die "no $ARCHIVES (debootstrap layout changed?)"
NDEB="$(ls "$ARCHIVES"/*.deb 2>/dev/null | wc -l)"
[ "$NDEB" -gt 0 ] || die "no .debs retained in $ARCHIVES"
log "rootless second stage: unpacking $NDEB debs"

# 3a. Fake /dev nodes: under fakeroot these are plain files; a real root run
# leaves real nodes. /dev stays empty either way (devtmpfs at boot).
if [ -d "$STAGING/dev" ]; then
    for node in "$STAGING"/dev/* "$STAGING"/dev/.udev; do
        [ -e "$node" ] || [ -L "$node" ] || continue
        if [ -b "$node" ] || [ -c "$node" ]; then
            log "keeping real device node $node"
        else
            rm -rf "$node"
        fi
    done
    log "/dev emptied (devtmpfs at boot)"
fi

INFO="$STAGING/var/lib/dpkg/info"
mkdir -p "$INFO"
STATUS_TMP="$(mktemp)"
CTRL_TMP="$(mktemp -d)"
trap 'rm -rf "$CTRL_TMP" "$STATUS_TMP"' EXIT
: > "$STATUS_TMP"
# Deterministic order (debootstrap's deburis order == dependency order).
while IFS= read -r deb; do
    [ -f "$deb" ] || continue
    pkg="$(dpkg-deb -f "$deb" Package)"
    # Data. debootstrap's first stage already extracted the required set, so
    # re-extraction must keep existing files (--skip-old-files: same outcome
    # as debootstrap's tar -k, but silent + exit 0 instead of noisy + exit 2).
    # Debian forbids undeclared cross-package overwrites, so skipping is safe.
    dpkg-deb --fsys-tarfile "$deb" | tar --skip-old-files -xf - -C "$STAGING"
    # Control files -> info/<pkg>.<member>.
    rm -rf "$CTRL_TMP" && mkdir -p "$CTRL_TMP"
    dpkg-deb -e "$deb" "$CTRL_TMP"
    for cf in "$CTRL_TMP"/*; do
        [ -f "$cf" ] || continue
        install -m 0644 "$cf" "$INFO/$pkg.$(basename "$cf")"
    done
    # .list (absolute paths, like dpkg --unpack would record).
    dpkg-deb -c "$deb" | awk '{print $6}' | sed -e 's|^\./|/|' -e 's|^//$|/|' \
        | grep -v '^/$' | sort -u > "$INFO/$pkg.list"
    # status stanza: full control paragraph + unpacked state.
    grep -vE '^(Status|Essential):' "$CTRL_TMP/control" >> "$STATUS_TMP" || true
    printf 'Status: install ok unpacked\n\n' >> "$STATUS_TMP"
done < <(for d in "$ARCHIVES"/*.deb; do echo "$d"; done | LC_ALL=C sort)
install -m 0644 "$STATUS_TMP" "$STAGING/var/lib/dpkg/status"
log "dpkg status: $(grep -c '^Package: ' "$STAGING/var/lib/dpkg/status") packages unpacked"

# 3b. passwd/group/shadow/gshadow from base-passwd masters (what update-passwd
# would create at configure time; PID1 needs root resolvable before that).
BP="$STAGING/usr/share/base-passwd"
[ -f "$BP/passwd.master" ] || die "missing $BP/passwd.master"
[ -f "$BP/group.master" ] || die "missing $BP/group.master"
sed 's/^\(.*\):\*:/\1:x:/' "$BP/passwd.master" > "$STAGING/etc/passwd"
cp "$BP/group.master" "$STAGING/etc/group"
# shadow: every passwd user locked '*', std aging fields (Debian fresh state).
awk -F: '{print $1":*:18000:0:99999:7:::"}' "$BP/passwd.master" > "$STAGING/etc/shadow"
awk -F: '{print $1":*::"}' "$BP/group.master" > "$STAGING/etc/gshadow"
chmod 0644 "$STAGING/etc/passwd" "$STAGING/etc/group"
chmod 0640 "$STAGING/etc/shadow" "$STAGING/etc/gshadow"
log "passwd/group/shadow created ($(wc -l < "$STAGING/etc/passwd") users, all locked)"

# 3c. sources.list: debootstrap wrote main-only; add components + updates + security.
{
    echo "deb $MIRROR $SUITE $(
        echo "$COMPONENTS" | tr ',' ' ')"
    echo "deb $MIRROR ${SUITE}-updates $(
        echo "$COMPONENTS" | tr ',' ' ')"
    echo "deb http://security.debian.org/debian-security ${SUITE}-security $(
        echo "$COMPONENTS" | tr ',' ' ')"
} > "$STAGING/etc/apt/sources.list"
chmod 0644 "$STAGING/etc/apt/sources.list"
log "sources.list extended ($(tr '\n' ';' < "$STAGING/etc/apt/sources.list"))"

# 3d. Manifests (dpkg -l format + provenance) BEFORE deleting the evidence.
PROV="$STAGING/usr/share/squeezebox/userland-provenance"
mkdir -p "$PROV"
cp "$STAGING/debootstrap/required" "$STAGING/debootstrap/base" \
    "$STAGING/debootstrap/deburis" "$STAGING/debootstrap/debootstrap.log" "$PROV/" 2>/dev/null || true
(cd "$ARCHIVES" && sha256sum ./*.deb > "$PROV/deb-sha256.txt")
{
    echo "# Squeezebox userland manifest (platform/rg35xx-h/rootfs/stage-userland.sh)"
    echo "# suite: $SUITE arch: $ARCH mirror: $MIRROR components: $COMPONENTS"
    echo "# debootstrap: --foreign --variant=minbase --include=[$INCLUDE_CSV]"
    echo "# release-verify: $VERIFY_STATE"
    echo "# second-stage: rootless-unpack (postinst runs natively at first boot)"
    echo "# epoch: $EPOCH"
    echo "# debs-sha256: /usr/share/squeezebox/userland-provenance/deb-sha256.txt"
    echo ""
    echo "Desired=Unknown/Install/Remove/Purge/Hold"
    echo "| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend"
    echo "|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)"
    echo "||/ Name                                        Version                    Architecture Description"
    echo "+++-===========================================-==========================-============-=================================================================="
    python3 - "$STAGING/var/lib/dpkg/status" <<'PYEOF'
import re, sys
stanzas = open(sys.argv[1]).read().split("\n\n")
rows = []
for s in stanzas:
    f = {}
    for line in s.splitlines():
        if line and line[0] not in " \t" and ":" in line:
            k, v = line.split(":", 1)
            f[k.strip()] = v.strip()
    if "Package" in f:
        desc = f.get("Description", "").split("\n")[0][:70]
        rows.append((f["Package"], f.get("Version", "?"), f.get("Architecture", "?"), desc))
for p, v, a, d in sorted(rows):
    print("iU  %-43.43s %-26.26s %-12.12s %s" % (p, v, a, d))
PYEOF
} > "$STAGING/userland-manifest.txt"
chmod 0644 "$STAGING/userland-manifest.txt"
log "manifest: $STAGING/userland-manifest.txt"

# 3e. Prune the build-only weight: /debootstrap helpers + the .deb cache.
rm -rf "$STAGING/debootstrap"
rm -f "$ARCHIVES"/*.deb
rm -rf "$ARCHIVES/partial"
log "pruned /debootstrap + .deb cache"

# 4. Epoch clamp for reproducibility (extraction times vary).
if [ "$EPOCH" != "0" ]; then
    find "$STAGING" -exec touch -h -d "@$EPOCH" {} +
    log "mtimes set to $EPOCH"
fi

NPKG="$(grep -c '^Package: ' "$STAGING/var/lib/dpkg/status")"
SIZE="$(du -sh "$STAGING" | cut -f1)"
log "userland ready: $STAGING ($NPKG packages, $SIZE)"
log "next: mkrootfs.sh --staging $STAGING --with-services --with-config"
