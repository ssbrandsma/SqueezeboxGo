#!/bin/sh
# service.sh — minimal pidfile service start/stop for standalone adapters.
# usage: service.sh start|stop|status <name> <pidfile> [command...]
# start: runs command detached (setsid), records pid. stop: TERM, grace,
# KILL. Refuses to manage pids it did not record.
set -u

die() { echo "service: $*" >&2; exit 1; }

cmd="${1:-}"; name="${2:-}"; pidfile="${3:-}"
[ -n "$cmd" ] && [ -n "$name" ] && [ -n "$pidfile" ] \
	|| die "usage: $0 start|stop|status <name> <pidfile> [command...]"
shift 3

is_running() {
	[ -f "$pidfile" ] || return 1
	pid=$(cat "$pidfile" 2>/dev/null) || return 1
	case "$pid" in ''|*[!0-9]*) return 1 ;; esac
	kill -0 "$pid" 2>/dev/null
}

case "$cmd" in
	start)
		[ $# -ge 1 ] || die "usage: $0 start <name> <pidfile> <command...>"
		if is_running; then echo "$name already running (pid $(cat "$pidfile"))"; exit 0; fi
		mkdir -p "$(dirname "$pidfile")"
		rm -f "$pidfile"
		# The supervising shell records its own pid so $! races (setsid
		# may fork) cannot stale the pidfile.
		setsid sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$pidfile" "$@" \
			>/dev/null 2>&1 < /dev/null &
		i=0
		while [ ! -f "$pidfile" ] && [ "$i" -lt 6 ]; do sleep 1; i=$((i+1)); done
		is_running || die "$name failed to start"
		echo "$name started (pid $(cat "$pidfile"))"
		;;
	stop)
		is_running || { echo "$name not running"; rm -f "$pidfile"; exit 0; }
		pid=$(cat "$pidfile")
		kill "$pid" 2>/dev/null || true
		i=0
		while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
		if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
		rm -f "$pidfile"
		echo "$name stopped"
		;;
	status)
		if is_running; then echo "$name running (pid $(cat "$pidfile"))"; exit 0; fi
		echo "$name not running"; exit 1
		;;
	*) die "usage: $0 start|stop|status <name> <pidfile> [command...]" ;;
esac
