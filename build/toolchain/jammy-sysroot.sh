#!/bin/sh
# jammy-sysroot.sh — rootless Ubuntu 22.04 (Jammy) arm64 sysroot for the
# jammy-staging squeezeplay variant (TRACK B1, branch diag/jammy-build).
#
# Why: the stock RG35XX H runs Jammy with glibc 2.35, but our noble-built
# payload needs GLIBC_2.38, so it cannot start there. Building against this
# sysroot (glibc 2.35 headers+libs) makes __isoc23-style refs unproducible:
# the whole staging tree then needs at most GLIBC_2.34 (measured).
#
# Provenance: same apt-download+extract technique as build-native-deps.sh and
# sysroot-notes.md ("Custom / rootless sysroots"), extended with (a) SHA256
# pinning against ports.ubuntu.com Packages.gz, (b) wrapper -B/-isystem flags
# (a bare --sysroot still picks the toolchain's noble 2.39 headers/libs —
# measured, see squeezeplay/configuration/jammy-staging.md).
#
# Usage:
#   build/toolchain/jammy-sysroot.sh [--prefix DIR] [--wrap DIR]
#       [--toolchain DIR] [--suite jammy-updates|jammy]
#   eval "$(build/toolchain/jammy-sysroot.sh --env [--prefix DIR] [--wrap DIR])"
#   build/toolchain/jammy-sysroot.sh --check [--prefix DIR] [--wrap DIR]
#
# Defaults: prefix ~/.cache/squeezeplay-jammy-sysroot, wrap <prefix>-wrap.
# --toolchain: dir holding the REAL aarch64-linux-gnu-gcc/g++/ld (default:
# resolved from PATH at creation time; the wrap dir itself is excluded).
# --check compiles a sscanf/strtol/ALSA probe and prints its max GLIBC.
# Rootless: never touches /usr, never needs sudo. Network: ports.ubuntu.com.
#
# After this, build with (see jammy-staging.md for the full recipe):
#   eval "$(... --env)"; cd <sp>/src
#   make -f Makefile.linux-aarch64 SYSROOT="$JAMMY_SYSROOT"

set -eu

BASE_URL="http://ports.ubuntu.com/ubuntu-ports"
PREFIX="${HOME}/.cache/squeezeplay-jammy-sysroot"
WRAP=""
TOOLCHAIN=""
SUITE="jammy-updates"
MODE="build"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
    --wrap) WRAP="$2"; shift 2 ;;
    --wrap=*) WRAP="${1#--wrap=}"; shift ;;
    --toolchain) TOOLCHAIN="$2"; shift 2 ;;
    --toolchain=*) TOOLCHAIN="${1#--toolchain=}"; shift ;;
    --suite) SUITE="$2"; shift 2 ;;
    --suite=*) SUITE="${1#--suite=}"; shift ;;
    --env) MODE="env"; shift ;;
    --check) MODE="check"; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$WRAP" ] || WRAP="${PREFIX}-wrap"

# Pinned debs (arm64, jammy-updates 2026-11-16; base-jammy fallback below).
# Columns: pool-path SHA256. All carry glibc 2.35 / ALSA 1.2.6.1.
if [ "$SUITE" = "jammy-updates" ]; then
  DEBS='
pool/main/g/glibc/libc6_2.35-0ubuntu3.18_arm64.deb 552390697756c005f8eff39b03392b2d8c6e148420c3e237d779fb44e54b5e72
pool/main/g/glibc/libc6-dev_2.35-0ubuntu3.18_arm64.deb debdc254b6dd8a95d91411475683b589e2094bfa7c5038b4fc5408120d3f3eab
pool/main/l/linux/linux-libc-dev_5.15.0-203.213_arm64.deb 4bd45d3028fd1c443d9cfaa61c14682ddcab9ab8a901b6a37b90253463cedfeb
pool/main/a/alsa-lib/libasound2_1.2.6.1-1ubuntu1.2_arm64.deb d9c6a79794e3cb8c46c2a87734a367eeb7f216cca7b58a533e836c33f3020eea
pool/main/a/alsa-lib/libasound2-dev_1.2.6.1-1ubuntu1.2_arm64.deb 18952a10a7632424bfb4e18581cf235e5a8ae6473638bb21ca813af896762dda
'
elif [ "$SUITE" = "jammy" ]; then
  DEBS='
pool/main/g/glibc/libc6_2.35-0ubuntu3_arm64.deb b1206b51690a810efc701e1d311e0ac5fd9a9f0f8e216585362512d805d261af
pool/main/g/glibc/libc6-dev_2.35-0ubuntu3_arm64.deb 2f254d6e843e413d549f407362885171c285f08383bb7e9392da855810ff78fd
pool/main/l/linux/linux-libc-dev_5.15.0-25.25_arm64.deb ffbdfcd181d87b92c108cb49ca20e152c0688825b5a1aac9ecbc63391b348aeb
pool/main/a/alsa-lib/libasound2_1.2.6.1-1ubuntu1_arm64.deb 5fd6e1c76664399be6233ca39c1f0db30cad36577f5466064ff8a95cdd0b28fb
pool/main/a/alsa-lib/libasound2-dev_1.2.6.1-1ubuntu1_arm64.deb 60a1144510d7a4b99d647eb9f9852519e89b69692fb377be580c241a247b11e2
'
else
  echo "ERROR: --suite must be jammy-updates or jammy" >&2
  exit 2
fi

# Resolve the REAL cross toolchain (never the wrap dir itself).
resolve_toolchain() {
  if [ -n "$TOOLCHAIN" ]; then
    echo "$TOOLCHAIN"
    return
  fi
  # Exclude $WRAP from PATH so we never wrap ourselves.
  clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -x "$WRAP" | paste -sd: -)"
  real_cc="$(PATH="$clean_path" command -v aarch64-linux-gnu-gcc || true)"
  if [ -z "$real_cc" ]; then
    echo "ERROR: no aarch64-linux-gnu-gcc on PATH (pass --toolchain DIR)" >&2
    exit 1
  fi
  dirname "$real_cc"
}

case "$MODE" in
  env)
    tc_dir=""
    if [ -f "$WRAP/aarch64-linux-gnu-gcc" ]; then
      # Reuse the toolchain the wrappers were created against.
      tc_dir="$(sed -n 's/^exec //; s/ .*//; s|/aarch64-linux-gnu-gcc$||p' \
        "$WRAP/aarch64-linux-gnu-gcc" | head -1)"
    fi
    [ -n "$tc_dir" ] || tc_dir="$TOOLCHAIN"
    echo "export JAMMY_SYSROOT=\"$PREFIX\""
    echo "export JAMMY_WRAP=\"$WRAP\""
    # PATH: wrappers first (shadow gcc/g++/ld), then the real toolchain.
    if [ -n "$tc_dir" ]; then
      echo "export PATH=\"$WRAP:$tc_dir:\$PATH\""
    else
      echo "export PATH=\"$WRAP:\$PATH\""
    fi
    # Rootless (relocated-deb) toolchains keep host libs beside the bindir
    # (libopcodes/libbfd); export them only when that layout is detected.
    # System-installed cross toolchains need none of this.
    if [ -n "$tc_dir" ]; then
      echo "case \" \$(ls $(dirname "$tc_dir")/lib/x86_64-linux-gnu/libopcodes* 2>/dev/null) \" in"
      echo "  *libopcodes*) export LD_LIBRARY_PATH=\"$(dirname "$tc_dir")/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\" ;;"
      echo "esac"
    fi
    echo "export SYSROOT_FOR_JAMMY=\"$PREFIX\""
    if [ ! -f "$PREFIX/usr/include/alsa/asoundlib.h" ]; then
      echo "echo 'NOTE: $PREFIX not assembled yet; run without --env first' >&2"
    fi
    ;;
  check)
    cc="$WRAP/aarch64-linux-gnu-gcc"
    if [ ! -x "$cc" ]; then
      echo "ERROR: $cc missing; run without --check first" >&2
      exit 1
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    cat > "$tmp/probe.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <alsa/asoundlib.h>
int main(void) {
    char b[64];
    long v = strtol("42", 0, 10);
    if (sscanf("7", "%63s", b) != 1) { return 1; }
    snprintf(b, sizeof b, "%ld %s", v, snd_asoundlib_version());
    printf("%s\n", b);
    return 0;
}
EOF
    "$cc" -march=armv8-a -o "$tmp/probe" "$tmp/probe.c" -lasound
    if nm "$tmp/probe" 2>/dev/null | grep -q '__isoc23'; then
      echo "CHECK FAIL: __isoc23 refs present (wrong headers win)" >&2
      exit 1
    fi
    maxv="$(readelf -V "$tmp/probe" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)"
    echo "probe max GLIBC: $maxv (want <= GLIBC_2.35)"
    case "$maxv" in
      GLIBC_2.3[0-5]) echo "CHECK OK" ;;
      *) echo "CHECK FAIL: too new" >&2; exit 1 ;;
    esac
    if command -v qemu-aarch64 >/dev/null 2>&1; then
      qemu-aarch64 -L "$PREFIX" "$tmp/probe"
    fi
    ;;
  build)
    for t in curl dpkg-deb; do
      command -v "$t" >/dev/null || { echo "ERROR: need $t" >&2; exit 1; }
    done
    tc_dir="$(resolve_toolchain)"
    for p in gcc g++ ld; do
      [ -x "$tc_dir/aarch64-linux-gnu-$p" ] || \
        { echo "ERROR: $tc_dir/aarch64-linux-gnu-$p missing" >&2; exit 1; }
    done
    mkdir -p "$PREFIX" "$PREFIX/.debs"
    echo "$DEBS" | grep -v '^$' | while read -r pool sha; do
      deb="$PREFIX/.debs/$(basename "$pool")"
      if [ -f "$deb" ]; then
        have="$(sha256sum "$deb" | cut -d' ' -f1)"
        if [ "$have" = "$sha" ]; then
          echo "cached OK: $(basename "$pool")"
        else
          echo "re-fetch (sha mismatch): $(basename "$pool")"
          rm -f "$deb"
        fi
      fi
      if [ ! -f "$deb" ]; then
        echo "fetch: $pool"
        curl -sS --fail --max-time 180 -o "$deb" "$BASE_URL/$pool"
        have="$(sha256sum "$deb" | cut -d' ' -f1)"
        [ "$have" = "$sha" ] || \
          { echo "ERROR: sha mismatch for $(basename "$pool")" >&2; exit 1; }
      fi
      dpkg-deb -x "$deb" "$PREFIX"
    done
    # Fix 1: absolute symlinks (/lib/...) must resolve INSIDE the sysroot.
    for l in $(find "$PREFIX" -type l); do
      t="$(readlink "$l")"
      case "$t" in
        /*) ln -sfn "$PREFIX$t" "$l" ;;
      esac
    done
    # Fix 2: GROUP paths in linker scripts need '=' so ld re-roots them
    # (same gotcha as sysroot-notes.md §Custom sysroots, item 3).
    if [ -f "$PREFIX/usr/lib/aarch64-linux-gnu/libc.so" ]; then
      sed -i 's|GROUP ( /lib|GROUP ( =/lib|; s| /usr/lib| =/usr/lib|g; s| ( /lib| ( =/lib|g' \
        "$PREFIX/usr/lib/aarch64-linux-gnu/libc.so"
    fi
    [ -f "$PREFIX/usr/include/alsa/asoundlib.h" ] || \
      { echo "ERROR: asoundlib.h missing after extract" >&2; exit 1; }
    [ -f "$PREFIX/usr/lib/aarch64-linux-gnu/crt1.o" ] || \
      { echo "ERROR: crt1.o missing after extract" >&2; exit 1; }
    # Fix 3: compiler wrappers. Bare --sysroot is NOT enough with a Debian
    # cross gcc: its install-relative noble include/lib dirs still win.
    # -B shadows startfiles+libs; -isystem (multiarch dir FIRST, then the
    # top dir — Debian order) shadows the noble 2.39 headers. Measured:
    # without -isystem, objects get __isoc23_* refs and the link fails
    # against 2.35 libc. The ld wrapper covers raw $(LD) links.
    mkdir -p "$WRAP"
    cat > "$WRAP/aarch64-linux-gnu-gcc" <<EOF
#!/bin/sh
S=$PREFIX
exec $tc_dir/aarch64-linux-gnu-gcc --sysroot=\$S -B\$S/usr/lib/aarch64-linux-gnu -isystem \$S/usr/include/aarch64-linux-gnu -isystem \$S/usr/include "\$@"
EOF
    cat > "$WRAP/aarch64-linux-gnu-g++" <<EOF
#!/bin/sh
S=$PREFIX
exec $tc_dir/aarch64-linux-gnu-g++ --sysroot=\$S -B\$S/usr/lib/aarch64-linux-gnu -isystem \$S/usr/include/aarch64-linux-gnu -isystem \$S/usr/include "\$@"
EOF
    cat > "$WRAP/aarch64-linux-gnu-ld" <<EOF
#!/bin/sh
S=$PREFIX
exec $tc_dir/aarch64-linux-gnu-ld --sysroot=\$S "\$@"
EOF
    chmod +x "$WRAP"/aarch64-linux-gnu-*
    echo "sysroot: $PREFIX"
    echo "wrappers: $WRAP (against $tc_dir)"
    echo "next: eval \"\$($0 --env --prefix $PREFIX --wrap $WRAP)\""
    ;;
esac
