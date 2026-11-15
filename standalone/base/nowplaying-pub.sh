#!/bin/sh
# nowplaying-pub.sh — publish the single authoritative Now Playing state.
# usage: nowplaying-pub.sh key=value [key=value...]
# Writes $NP_STATE_DIR/nowplaying.json atomically per
# standalone/base/nowplaying-schema.md. Keys not given keep their
# previous value from the existing state file (absent file = all null).
# jq-free so it runs on the target busybox image.
set -u
STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}"
STATE_FILE="$STATE_DIR/nowplaying.json"

STR_KEYS="source_id player_id mode track artist album station repeat shuffle
	format output_device artwork_icon artwork_size"
RAW_KEYS="is_local power seekable volume position_s duration_s rate_hz
	depth_bits pl_index pl_size"

json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
		-e 's/\t/\\t/g' | tr -d '\n\r'
}

# get_prev <key>: print previous value decoded to one of:
#   S:<string>   JSON string (quotes removed, escapes intact)
#   N:<number|true|false>   JSON literal
#   (nothing)    key absent or JSON null
get_prev() {
	[ -f "$STATE_FILE" ] || return 0
	raw=$(sed -n "s/^[[:space:]]*\"$1\":[[:space:]]*\(.*\)$/\1/p" "$STATE_FILE" \
		| head -1 | sed 's/[[:space:]]*,[[:space:]]*$//') || return 0
	case "$raw" in
		'"'*'"')
			raw="${raw#\"}"; raw="${raw%\"}"
			# decode the escapes json_escape produces
			raw=$(printf '%s' "$raw" | sed -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g')
			printf 'S:%s' "$raw"
			;;
		null|'') return 0 ;;
		*) printf 'N:%s' "$raw" ;;
	esac
}

# state accessors; values stored shell-side as S:... / N:... / empty
s_get() { eval "printf '%s' \"\${prev_$1:-}\""; }
s_set() { eval "prev_$1=\"\$2\""; }

for k in $STR_KEYS $RAW_KEYS; do s_set "$k" "$(get_prev "$k")"; done

is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

for arg in "$@"; do
	case "$arg" in *=*) k="${arg%%=*}"; v="${arg#*=}" ;;
		*) echo "nowplaying-pub: bad arg (want key=value): $arg" >&2; exit 1 ;; esac
	case " $STR_KEYS " in
		*" $k "*)
			if [ -z "$v" ]; then s_set "$k" ""; else s_set "$k" "S:$v"; fi ;;
		*) : ;;
	esac
	case " $RAW_KEYS " in
		*" $k "*)
			case "$k" in
				is_local|power|seekable)
					case "$v" in true|false) s_set "$k" "N:$v" ;;
						'') s_set "$k" "" ;;
						*) echo "nowplaying-pub: $k wants true|false" >&2; exit 1 ;; esac ;;
				*)
					if [ -z "$v" ]; then s_set "$k" "";
					elif is_num "$v"; then s_set "$k" "N:$v";
					else echo "nowplaying-pub: $k wants a number" >&2; exit 1; fi ;;
			esac ;;
		*) : ;;
	esac
	case " $STR_KEYS $RAW_KEYS " in
		*" $k "*) : ;;
		*) echo "nowplaying-pub: unknown key: $k" >&2; exit 1 ;;
	esac
done

# emit <key>: full JSON value (quoted string or literal or null)
emit() {
	val="$(s_get "$1")"
	case "$val" in
		S:*) printf '"%s"' "$(json_escape "${val#S:}")" ;;
		N:*) printf '%s' "${val#N:}" ;;
		*) printf 'null' ;;
	esac
}

mkdir -p "$STATE_DIR"
tmp="$STATE_FILE.$$"
{
	echo '{'
	echo "  \"schema\": 1,"
	echo "  \"updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
	for k in source_id player_id is_local power mode track artist album \
			station position_s duration_s seekable volume repeat shuffle \
			format rate_hz depth_bits output_device; do
		case "$k" in
			station)
				printf '  "%s": %s,\n' "$k" "$(emit "$k")"
				printf '  "artwork": { "icon_id": %s, "size": %s },\n' \
					"$(emit artwork_icon)" "$(emit artwork_size)" ;;
			shuffle)
				printf '  "%s": %s,\n' "$k" "$(emit "$k")"
				printf '  "playlist": { "index": %s, "size": %s },\n' \
					"$(emit pl_index)" "$(emit pl_size)" ;;
			output_device)
				printf '  "%s": %s\n' "$k" "$(emit "$k")" ;;
			*)
				printf '  "%s": %s,\n' "$k" "$(emit "$k")" ;;
		esac
	done
	echo '}'
} > "$tmp"
mv "$tmp" "$STATE_FILE"
echo "published $STATE_FILE"
