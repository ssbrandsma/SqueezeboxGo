#!/usr/bin/env bash
# build.sh — build the image container and run a repo command inside it.
#
# Usage:
#   build/docker/build.sh --image-name NAME [--rebuild] -- <command...>
#   build/docker/build.sh --help
#
# Example:
#   build/docker/build.sh -- ./build/image/assemble-image.sh --check-deps
# The repo root is mounted at /work/repo (read-write); output lands in the
# repo (build/cache/, releases/). Fails closed when docker is unavailable.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

log() { printf 'build.sh: %s\n' "$*"; }
die() { printf 'build.sh: ERROR: %s\n' "$*" >&2; exit 1; }

NAME="squeezebox-image" REBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --image-name) NAME="$2"; shift 2 ;;
        --rebuild) REBUILD=1; shift ;;
        --) shift; break ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown arg: $1 (commands go after --)" ;;
    esac
done
[ $# -gt 0 ] || die "no command given (see --help)"
command -v docker >/dev/null 2>&1 || die "docker not installed"

if [ "$REBUILD" = 1 ] || ! docker image inspect "$NAME" >/dev/null 2>&1; then
    log "building $NAME"
    docker build -t "$NAME" -f "$HERE/Dockerfile" "$HERE"
fi
log "running in $NAME: $*"
exec docker run --rm -v "$REPO_ROOT:/work/repo" -w /work/repo "$NAME" "$@"
