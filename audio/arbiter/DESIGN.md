# Audio-owner arbiter — design (WP1)

Contract owner: Agent 3 (Audio). Consumers: squeezeplay launcher
(Agent 2), standalone sources (Agent 5). Normative contract phrases come
from `docs/interface-contracts.md` ("Audio ownership") and ADR-0003.

## Requirements

1. Exactly one active playback source holds the ALSA device.
2. `audio-owner acquire|release <source>`; a crashed holder's claim
   evaporates without operator action.
3. Consistent volume/mute across switches; Now Playing updated on every
   switch; no stale metadata (arbiter emits switch events; Agent 5
   consumes them — this repo only defines the event line format).
4. Works from shell launchers with zero dependencies beyond POSIX sh +
   `flock(1)` (util-linux, present on target) + `/proc`.

## Design

State directory: `/run/squeezebox-audio` (tmpfs, root-owned; override
with `AUDIO_OWNER_DIR` for tests). Files:

- `mutex` — empty file; all state transitions run under `flock -x` on
  it, so check-and-claim is atomic across processes.
- `owner` — single line `source=<name> pid=<pid> starttime=<stime>
  since=<epoch>` while held; absent when free. `starttime` is field 22
  of `/proc/<pid>/stat` (guards against PID reuse).

Claim rule: a claim is live iff `owner` exists AND parses (all of
`source/pid/starttime` present) AND `/proc/<pid>/stat` exists AND its
field-22 equals the recorded `starttime`. Anything else is stale and
is reaped — by the next `acquire`/`release`/`status`, whichever runs
first — with a `reaped` event on stdout before the operation proceeds.
Because liveness is re-derived from the kernel on every operation,
**no daemon, no heartbeat, and no cleanup hook is needed**: kill -9
anywhere in the chain still converges on the truth.

WP2 hardening notes (vs the WP1 reference):

- Claims are written atomically (`owner.tmp.<pid>` + rename), so a
  kill mid-write leaves at worst an orphaned temp file, never a torn
  record; `init_dir` sweeps temp files whose writer pid is dead.
- A present-but-unparseable record (e.g. written by a killed WP1
  arbiter) is treated as stale-with-identity (`source=?`), reaped
  loudly — never silently dropped, never mistaken for free.
- `status` is read-only when there is no state (no directory creation
  side effect) and reaps stale records it finds: it reports under a
  shared lock, then drops it and re-takes the mutex exclusively for
  the reap (no SH→EX in-place upgrade, which could deadlock two
  concurrent readers).
- `hold` forwards TERM/INT to the child, verifies the claim is still
  ours before re-pointing it at the child pid, and propagates the
  `acquire` exit code instead of collapsing it to 1.
- Source names are restricted to `[A-Za-z0-9._-]+` so the owner line
  and event lines stay machine-parseable; diagnostics go to stderr
  with a timestamp, event lines always to stdout (including the
  `force-release` event, which WP1 misdirected to stderr).

Two usage modes:

- `acquire <source> [--pid PID]` / `release <source>`: for launchers.
  `--pid` defaults to the caller's PID; pass the *player* PID
  (e.g. the `jive_alsa` child) when the launcher is a short-lived
  wrapper so the claim tracks the process that actually holds ALSA.
- `hold <source> -- <cmd> [args...]`: runs `<cmd>` as a child, claims
  on its behalf with the child's PID, and releases when it exits
  (exit code propagated). Crash of `<cmd>` ⇒ next acquire reaps.
  This is the recommended mode for `squeezeplay.sh` and standalone
  adapters.

Additional commands: `status` (prints `free` or the owner line;
exit 0 held / 3 free; reaps stale records it finds), `wait
[--timeout S]` (polls 5 Hz until free; exit 0 free / 4 timeout),
`force-release` (operator escape hatch, logs loudly). Every
acquire/release/reap/timeout prints a single event line to stdout:

```
audio-owner event=<acquired|released|reaped|timeout> source=<name> pid=<pid> ts=<epoch>
```

Now Playing publishers (Agent 5) tail these lines; the arbiter itself
never touches metadata stores (no stale-metadata path by construction).

Volume/mute consistency is by convention, not enforcement: all sources
use the same control set (`audio/alsa/mixer-controls.md`) and must not
cache levels across a switch — re-read on acquire. The arbiter does not
store volume (a second source of truth would be the stale-metadata bug
the contract forbids).

## Failure analysis

| Failure | Behavior |
|---|---|
| Holder SIGKILLed | Claim reaped on next acquire/release/status; `reaped` event emitted |
| PID reused before reap | `starttime` mismatch ⇒ still reaped |
| Two racers acquire | `flock` mutex serializes; exactly one wins |
| Arbiter SIGKILLed mid-claim | Atomic tmp+rename: no torn record; orphaned temp swept on next init |
| `/run` wiped (reboot) | State gone ⇒ free; correct, nothing is playing |
| `release` by non-holder | Refused (exit 5), state untouched |
| Holder forked children holding ALSA fd | Out of scope: sources must `exec` the player, not orphan it; `hold` mode covers the standard case |
| `hold` wrapper SIGTERMed | TERM forwarded to child; claim evaporates via reap if child dies |
| Malformed `owner` record | Treated as stale-with-identity, reaped loudly (never silent-drop) |
| flock(1) missing | Fail closed: refuse to claim (exit 2) rather than allow double-hold |

## Alternatives considered

- Kernel-held `flock` on a lockfile per holder (`exec 9>lock; flock -n 9`):
  truly instant release, but ownership does not survive `exec`-less
  wrapper exits and cannot name the source; rejected as the primary
  mechanism, kept implicitly as the mutex.
- PulseAudio/PipeWire session manager: contradicts the X-less,
  single-holder ALSA architecture (ADR-0003); rejected.
- D-Bus service: no bus on the minimal image; rejected.
