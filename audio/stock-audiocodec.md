# Stock audio: `audiocodec` ALSA path (vendor 4.9 kernel track)

Scope: audio on the **stock** card (vendor 4.9.170, BSP `sun50iw9` audio
driver). Verified inventory ([hardware](../docs/hardware.md#verified-audio-alsa)):

- Cards: 0 `audiocodec`, 1 `ahubdam`, 2 `ahubhdmi`.
- Playback PCMs: `hw:CARD=audiocodec,DEV=0`, `plughw:...`,
  `hw:CARD=ahubhdmi`, plus `playback_hp`, `playback_hdmi`, `bluealsa`.
- Mixers seen: LINEOUT, OutputL/R Mixer DACL/DACR, SPK, digital volume,
  lineout volume, tx hub mode.
- **The internal PCM was occupied during inventory.**

B2 stock track: guidance + probe commands only. No change to shipped
audio code (`audio/alsa/asound.conf`, `audio/arbiter/*` are the mainline
track and are untouched by this doc).

## 1. Device strings on stock

| Purpose | Preferred string | Fallback |
|---|---|---|
| Internal speaker/headphone (direct) | `hw:CARD=audiocodec,DEV=0` | `plughw:CARD=audiocodec,DEV=0` |
| Internal via plug/conversion | `plug:playback_hp` if listed by `aplay -L` | `default` (only after confirming where stock `default` points) |
| HDMI audio | `hw:CARD=ahubhdmi,DEV=0` | `plug:playback_hdmi` |
| Bluetooth (if stack present) | `bluealsa` device per `aplay -L` | — |

Rules:

- `hw:` = exact native open, no conversion; fails if rate/format is
  unsupported or the PCM is busy (`-EBUSY`). `plughw:`/`plug:` adds
  ALSA-side conversion but still fails when busy.
- For `jive_alsa` (`USEALSADEVICE` env, cf. `audio/ALSA_PATH.md` §2):
  start with `plughw:CARD=audiocodec,DEV=0` on stock — the BSP driver's
  rate/format matrix is unverified, and the plug layer absorbs that —
  then narrow to `hw:` once `aplay --dump-hw-params` (§4) shows the real
  matrix. Never point stock at the mainline `asound.conf` aliases
  (`internal`/`usb`): they assume card `H616 Audio Codec` at index 0
  with mainline control names and do not exist on the vendor driver.
- Do NOT overwrite stock `/etc/asound.conf` — read it first
  (`cat /etc/asound.conf /usr/share/alsa/alsa.conf.d/* 2>/dev/null`);
  stock may already define `playback_hp`/`playback_hdmi` there.

## 2. Mixer init from verified controls (template, confirm names first)

The control names below are the **vendor BSP names from inventory**
(LINEOUT, Output L/R Mixer DACL/DACR, SPK, digital volume, lineout
volume, tx hub mode) — they are NOT the mainline sun4i-codec names in
`audio/alsa/mixer-controls.md`. BSP `amixer` names must be copied exactly
from `amixer -c 0 scontents` output (§4) before scripting; the sequence
below is a template with the expected shape:

```sh
C=0  # CARD=audiocodec; re-resolve with aplay -l if numbering shifts
amixer -c $C scontents > /tmp/stock-scontents.txt 2>&1   # capture first

# Expected shape (ADAPT every name to the captured scontents):
amixer -c $C sset '<digital volume>' 0dB        # unity digital trim
amixer -c $C sset '<Lineout volume>' -12dB      # safe analog start level
amixer -c $C sset '<LINEOUT switch>' on
amixer -c $C sset '<Output Left Mixer DACL>' on
amixer -c $C sset '<Output Right Mixer DACR>' on
amixer -c $C sset '<SPK switch>' on
amixer -c $C sset '<tx hub mode>' '<playback value from scontents>'
```

Policy (mirrors `audio/alsa/mixer-controls.md` §"Recommended policy"):

1. Digital trim fixed at unity; volume keys drive the analog lineout
   control so later bit-perfect checks stay meaningful.
2. Unmute/route before first playback; keep the captured
   `stock-scontents.txt` as the before/after diff baseline
   (`amixer -c 0 scontents > /tmp/after.txt; diff`).
3. If a name from inventory is absent in `scontents`, STOP and record —
   do not guess a renamed equivalent; the BSP driver revision may differ.

## 3. Owner identification FIRST (mandatory pre-flight)

The internal PCM was occupied at inventory time. Any exclusive open
before identifying the holder risks `-EBUSY` failures or fighting a
stock daemon (vendor launcher audio, bluetooth stack, login sounds).
**Always run this pre-flight before any playback attempt on stock:**

```sh
# 3a. Kernel PCM state (owner_pid when open)
cat /proc/asound/card0/pcm0p/info
cat /proc/asound/card0/pcm0p/sub0/status   # state: CLOSED = free
grep -H . /proc/asound/card*/pcm*p/sub*/status 2>/dev/null | grep -E 'state|owner_pid'
# 3b. Process holders (both; fuser ships with psmisc, lsof may be absent)
fuser -v /dev/snd/* 2>&1
lsof /dev/snd/* 2>&1 || echo "(lsof absent)"
ls -l /dev/snd/
# 3c. Identify the holder binary + its parent service
ps -o pid,ppid,comm,args -p <PID-from-3a-or-3b>
systemctl status <PID> 2>/dev/null || cat /proc/<PID>/cmdline | tr '\0' ' '; echo
```

Decision rule:

- `state: CLOSED` + no `fuser` output → PCM free, proceed.
- A holder exists → record PID/comm/service in the evidence; do NOT kill
  it as part of probing. Playback on stock waits until the holder is
  understood (see §5 for the arbiter consequences).

## 4. Capability probes (read-only)

```sh
cat /proc/asound/cards
cat /proc/asound/devices
aplay -l; aplay -L
amixer -c 0 scontents
aplay -D hw:0,0 --dump-hw-params /dev/null 2>&1 | head -40
cat /proc/asound/card0/pcm0p/info
cat /etc/asound.conf 2>/dev/null; ls /usr/share/alsa/alsa.conf.d/ 2>/dev/null
```

What to record: card index↔name binding, `aplay -L` alias list
(`playback_hp`? `playback_hdmi`? `bluealsa`?), `scontents` full text,
hw-params RATE/FORMAT matrix, and whether stock `default` exists and
where it points.

## 5. Why the audio-owner arbiter must treat stock daemons as foreign holders

`audio-owner` (`audio/arbiter/audio-owner`, design in
`audio/arbiter/DESIGN.md`) tracks **only claims made through itself**:
a claim is live iff its recorded PID is alive with a matching starttime
(fields re-derived from `/proc` each operation). It knows nothing about
processes that open ALSA without acquiring — which is every stock daemon.

Consequences on the stock track:

1. **Arbiter "free" ≠ ALSA free.** A vendor launcher holding
   `hw:CARD=audiocodec` never appears in `/run/squeezebox-audio/owner`,
   so `audio-owner status` reports `free` while `snd_pcm_open` returns
   `-EBUSY`. Any stock launcher MUST run the §3 pre-flight (status +
   `fuser`) and treat a foreign holder as "held", independent of the
   arbiter state.
2. **`force-release` cannot free a foreign holder.** It only deletes our
   own claim file; the daemon keeps the fd. Never present it as a fix
   for EBUSY on stock — it would report success while playback still
   fails.
3. **No killing stock daemons from scripts.** Stopping/reconfiguring a
   stock audio service is a user-executed, reversible action (second-card
   safety: preferably tested by booting our own card image, or by the
   user disabling the service on stock with a documented re-enable).
   Scripts stop at *identifying* the holder.
4. **Single-holder policy still applies.** No `dmix` layer to paper over
   contention (same rationale as mainline `asound.conf`: one holder,
   less latency, fewer failure modes). Contention is resolved by
   ownership handoff (stock service off → our source acquires), never by
   mixing.

Recommended stock acquire wrapper (for the future stock launcher; sketch,
not shipped code):

```sh
# 1. arbiter domain check
audio-owner acquire jive-stock || exit 1
# 2. kernel domain check (foreign holders)
if fuser /dev/snd/pcmC0D0p >/dev/null 2>&1; then
  echo "foreign ALSA holder: $(fuser -v /dev/snd/pcmC0D0p 2>&1)"
  audio-owner release jive-stock
  exit 1
fi
# 3. proceed to exec jive_alsa ...
```

## 6. Relation to mainline audio files (do not cross the streams)

- `audio/alsa/asound.conf` (aliases `internal`/`usb`, card-index pinning,
  `H616 Audio Codec` assumptions) does NOT apply to stock — stock keeps
  its own ALSA config; overrides travel via `USEALSADEVICE`-style env.
- `audio/alsa/capability-detect.sh` matches internal cards by
  `H616 Audio Codec`/`sun4i-codec` names and will report
  `internal.card=-1` on stock (card is `audiocodec`). Reuse its
  `key=value` contract for a stock probe, but match `audiocodec`, and
  treat `-1` as "stock naming", not "no hardware".
- `audio/tests/topology-probe.sh` asserts mainline topology
  (`H616AudioCodec`, `CDC PCM`, no `stream0`, kconf cross-checks) and is
  expected to FAIL on stock — that failure is a correct
  mainline-vs-vendor discriminator, not a bug.
