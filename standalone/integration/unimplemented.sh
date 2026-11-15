#!/bin/sh
# unimplemented.sh — backend placeholder for services with no real sources.
# usage: unimplemented.sh <source-id> <reason...>
# Always exits 3. Satisfies the adapter's BACKEND_CMD slot without
# fabricating a backend. See standalone/REQUIRED_SOURCES.md items 9-14.
set -u
src="${1:-?}"; shift || true
echo "UNIMPLEMENTED backend '$src': $*" >&2
exit 3
