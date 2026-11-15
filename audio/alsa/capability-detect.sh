#!/bin/sh
# capability-detect.sh — ALSA capability detection for RG35XX H (WP1)
#
# Enumerates sound cards and playback capabilities without libasound:
# reads /proc/asound + /sys and, when present, aplay/amixer. Prints
# machine-readable `key=value` lines (stable contract, consumed by the
# audio-owner setup, image scripts, and audio/tests/) followed by a
# human summary on stderr.
#
# Usage: capability-detect.sh [--proc-asound DIR] [--sys-root DIR] [--quiet]
#
# Contract (stdout, `key=value`, one per line):
#   card.count=N
#   card.<i>.index / .id / .name / .driver / .usb (0/1)
#   card.<i>.pcm.<d>.info        "<channels>ch <formats...>"  (from pcmXp/info)
#   card.<i>.pcm.<d>.rates       "<rate list>"                (from stream0 or hw_params constraints)
#   internal.card=<index|-1>     (-1 = not found)
#   usb.card=<index|-1>          (first snd-usb-audio card)
#   suggest.ALSA_INTERNAL_CARD / suggest.ALSA_USB_CARD / suggest.ALSA_USB_PCM
# Exit 0 always unless the proc tree is unreadable (exit 2) or no cards
# at all were found (exit 1; still prints what it could).
#
# Mirrors the squeezelite test_open() probe order (open → hw constraints →
# rate matrix) at shell level; see audio/ALSA_PATH.md §6.

set -u

PROC_ASOUND="${PROC_ASOUND:-/proc/asound}"
SYS_ROOT="${SYS_ROOT:-/sys}"
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --proc-asound) PROC_ASOUND="$2"; shift 2 ;;
        --sys-root) SYS_ROOT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }

[ -r "$PROC_ASOUND/cards" ] || { echo "cannot read $PROC_ASOUND/cards" >&2; exit 2; }

# --- card list -------------------------------------------------------------
# /proc/asound/cards format: " <idx> [ <id> ]: <driver> - <name>"
count=0
internal=-1
usbfirst=-1

tmp_cards="$(mktemp)"; trap 'rm -f "$tmp_cards"' EXIT INT TERM
grep -E '^ *[0-9]+ \[' "$PROC_ASOUND/cards" > "$tmp_cards" || true

while IFS= read -r line; do
    idx="$(printf '%s' "$line" | sed -E 's/^ *([0-9]+) \[.*/\1/')"
    id="$(printf '%s' "$line" | sed -E 's/^ *[0-9]+ \[([^]]*)\].*/\1/' | tr -d ' ')"
    rest="$(printf '%s' "$line" | sed -E 's/^ *[0-9]+ \[[^]]*\]: //')"
    driver="$(printf '%s' "$rest" | sed -E 's/ - .*//')"
    name="$(printf '%s' "$rest" | sed -E 's/^.* - //')"
    carddir="$PROC_ASOUND/card$idx"

    is_usb=0
    case "$driver" in
        *USB*|*usb*) is_usb=1 ;;
    esac
    [ -e "$carddir/usbid" ] && is_usb=1
    if [ -e "$SYS_ROOT/class/sound/card$idx/device/driver" ]; then
        drvlink="$(readlink "$SYS_ROOT/class/sound/card$idx/device/driver" 2>/dev/null || true)"
        case "$drvlink" in *snd-usb-audio*) is_usb=1 ;; esac
    fi

    printf 'card.%s.index=%s\n' "$count" "$idx"
    printf 'card.%s.id=%s\n' "$count" "$id"
    printf 'card.%s.name=%s\n' "$count" "$name"
    printf 'card.%s.driver=%s\n' "$count" "$driver"
    printf 'card.%s.usb=%s\n' "$count" "$is_usb"

    case "$name" in
        *"H616 Audio Codec"*|*"sun4i-codec"*|*"H6"[0-9]*" Audio Codec"*)
            [ "$internal" -eq -1 ] && internal="$idx" ;;
    esac
    if [ "$is_usb" -eq 1 ] && [ "$usbfirst" -eq -1 ]; then usbfirst="$idx"; fi

    # --- playback PCMs on this card ---------------------------------------
    for info in "$carddir"/pcm*p/info; do
        [ -r "$info" ] || continue
        dev="$(printf '%s' "$info" | sed -E 's/.*pcm([0-9]+)p\/info/\1/')"
        sub="$(sed -n 's/^subdevices_count: *//p' "$info" | head -1)"
        chs="$(sed -n 's/^subdevices_avail: *//p' "$info" | head -1)"
        printf 'card.%s.pcm.%s.subdevices=%s\n' "$count" "$dev" "${sub:-?}"
        printf 'card.%s.pcm.%s.avail=%s\n' "$count" "$dev" "${chs:-?}"
        idline="$(sed -n 's/^id: *//p' "$info" | head -1)"
        nameline="$(sed -n 's/^name: *//p' "$info" | head -1)"
        printf 'card.%s.pcm.%s.id=%s\n' "$count" "$dev" "${idline:-?}"
        printf 'card.%s.pcm.%s.name=%s\n' "$count" "$dev" "${nameline:-?}"
    done

    # --- rate/format matrix ----------------------------------------------
    # stream0 exists on USB + some ASoC cards and lists altsetting rates.
    if [ -r "$carddir/stream0" ]; then
        rates="$(grep -oE 'Rates: [0-9, ]+' "$carddir/stream0" | head -1 | sed 's/Rates: //')"
        fmts="$(grep -oE 'Formats: [A-Za-z0-9_, ]+' "$carddir/stream0" | head -1 | sed 's/Formats: //')"
        printf 'card.%s.rates=%s\n' "$count" "${rates:-?}"
        printf 'card.%s.formats=%s\n' "$count" "${fmts:-?}"
    elif command -v aplay >/dev/null 2>&1; then
        # Fallback: parse `aplay --dump-hw-params` for hw:<idx>,0.
        dump="$(aplay -D "hw:$idx,0" --dump-hw-params /dev/null 2>/dev/null | tr '\n' ' ' || true)"
        if [ -n "$dump" ]; then
            printf 'card.%s.rates=%s\n' "$count" \
                "$(printf '%s' "$dump" | grep -oE 'RATE: \[[^]]*\]' | head -1)"
            printf 'card.%s.formats=%s\n' "$count" \
                "$(printf '%s' "$dump" | grep -oE 'FORMAT: \[[^]]*\]' | head -1)"
        else
            printf 'card.%s.rates=?\n' "$count"
            printf 'card.%s.formats=?\n' "$count"
        fi
    else
        printf 'card.%s.rates=?\n' "$count"
        printf 'card.%s.formats=?\n' "$count"
    fi

    count=$((count + 1))
done < "$tmp_cards"

printf 'card.count=%s\n' "$count"
printf 'internal.card=%s\n' "$internal"
printf 'usb.card=%s\n' "$usbfirst"
if [ "$internal" -ne -1 ]; then
    printf 'suggest.ALSA_INTERNAL_CARD=%s\n' "$internal"
else
    printf 'suggest.ALSA_INTERNAL_CARD=0\n'
fi
if [ "$usbfirst" -ne -1 ]; then
    printf 'suggest.ALSA_USB_CARD=%s\n' "$usbfirst"
    printf 'suggest.ALSA_USB_PCM=usb\n'
else
    printf 'suggest.ALSA_USB_CARD=1\n'
    printf 'suggest.ALSA_USB_PCM=internal\n'
fi

log "--- ALSA capability summary ($PROC_ASOUND) ---"
log "cards: $count, internal H616 card index: $internal, first USB card index: $usbfirst"
if command -v amixer >/dev/null 2>&1 && [ "$internal" -ne -1 ]; then
    log "internal-card controls:"
    amixer -c "$internal" scontents 2>/dev/null | grep -E "^Simple mixer control" | sed 's/^/  /' >&2 || true
fi

[ "$count" -gt 0 ] || exit 1
exit 0
