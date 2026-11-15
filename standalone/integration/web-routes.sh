#!/bin/sh
# web-routes.sh — registry for standalone web-management routes.
# Contract duty: adapters expose web routes. This registry is the single
# place where a source backend declares "METHOD path handler"; the web
# server (WP3) reads the merged table. No server is implemented here.
#
# usage: web-routes.sh register <plugindir>   — validate + print routes
#        web-routes.sh list <plugindir>...    — merged route table
# routes.conf format (one per line, '#' comments, blank lines skipped):
#   METHOD /path handler-name
set -u

die() { echo "web-routes: $*" >&2; exit 1; }

valid_method() {
	case "$1" in GET|POST|PUT|DELETE) return 0 ;; *) return 1 ;; esac
}

show_routes() { # $1=plugindir
	[ -f "$1/routes.conf" ] || { echo "# no routes.conf in $1"; return 0; }
	src="$(basename "$1")"
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in ''|'#'*) continue ;; esac
		# shellcheck disable=SC2086
		set -- $line
		[ $# -eq 3 ] || die "$1/routes.conf: bad line: $line"
		valid_method "$1" || die "$1/routes.conf: bad method: $1"
		case "$2" in /*) ;; *) die "$1/routes.conf: path must start with /: $2" ;; esac
		printf '%-6s %-28s %s %s\n' "$1" "$2" "$3" "(src=$src)"
	done < "$1/routes.conf"
}

case "${1:-}" in
	register|list) op="$1"; shift ;;
	*) die "usage: $0 register <plugindir> | list <plugindir>..." ;;
esac
[ $# -ge 1 ] || die "usage: $0 $op <plugindir>..."
for d in "$@"; do show_routes "$d"; done
