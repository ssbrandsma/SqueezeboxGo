#!/usr/bin/env bash
# Release checksum tooling. Usage:
#   releases/checksum.sh create <dir>   # write sorted SHA256SUMS in <dir>
#   releases/checksum.sh verify <dir>   # verify SHA256SUMS in <dir>
set -u
cmd="${1:-}"; dir="${2:-}"
[ -n "$cmd" ] && [ -n "$dir" ] || { echo "usage: checksum.sh create|verify <dir>" >&2; exit 2; }
[ -d "$dir" ] || { echo "not a directory: $dir" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "sha256sum missing" >&2; exit 4; }

case "$cmd" in
  create)
    ( cd "$dir" && rm -f SHA256SUMS.tmp &&
      find . -maxdepth 1 -type f ! -name 'SHA256SUMS*' -printf '%P\n' | LC_ALL=C sort |
      while IFS= read -r f; do sha256sum "$f"; done > SHA256SUMS.tmp &&
      mv SHA256SUMS.tmp SHA256SUMS )
    echo "wrote $dir/SHA256SUMS:"; cat "$dir/SHA256SUMS";;
  verify)
    [ -f "$dir/SHA256SUMS" ] || { echo "no SHA256SUMS in $dir" >&2; exit 4; }
    ( cd "$dir" && sha256sum -c SHA256SUMS );;
  *) echo "unknown command: $cmd" >&2; exit 2;;
esac
