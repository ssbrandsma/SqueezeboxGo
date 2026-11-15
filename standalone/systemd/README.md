# Standalone systemd proposal (WP2, for platform-agent integration)

Owner: Agent 5. Status: **proposal** — the platform agent (Agent 1)
owns `platform/rg35xx-h/rootfs` + `platform/rg35xx-h/services` and
decides what lands there. This directory is shaped like the platform
overlay (`overlay/<target-path>` mirrors `rootfs/overlay/`) so the
unit files can move over verbatim.

## What is proposed

One template unit per playback source plus a grouping target:

- `overlay/usr/lib/systemd/system/squeezebox-source@.service` —
  `squeezebox-source@<id>` runs
  `adapter.sh <id> start|stop /etc/squeezebox/standalone/services/<id>`.
  `Type=oneshot` + `RemainAfterExit=yes` follows the existing
  `wifi.service` pattern: the adapter supervises the backend via
  `service.sh` (pidfile in `/run/squeezebox`), systemd tracks
  start/stop state. No adapter changes needed.
- `overlay/usr/lib/systemd/system/squeezebox-standalone.target` —
  grouping target, `WantedBy=multi-user.target`.

## Install layout (target paths)

| Repo file(s) | Target path | Mode |
|---|---|---|
| `standalone/base/*.sh` | `/usr/lib/squeezebox/standalone/base/` | 0755 |
| `standalone/integration/*.sh`, `*.lua` | `/usr/lib/squeezebox/standalone/integration/` | 0755 (`*.sh`), 0644 (`*.lua`) |
| `standalone/integration/services/<id>/{backend,routes}.conf` | `/etc/squeezebox/standalone/services/<id>/` | 0644 |
| `standalone/systemd/overlay/usr/lib/systemd/system/*` | `/usr/lib/systemd/system/` | 0644 |

Code is read-only under `/usr/lib`; per-source `backend.conf` /
`routes.conf` live under `/etc` so a backend swap (WP3) is a config
edit, not an image rebuild. Suggested `mkrootfs.sh` shape: a
`--with-standalone` step mirroring `--with-services` (install +
no enables by default, see below).

## Enable policy: ship disabled

All 8 shipped backends are UNIMPLEMENTED (`unimplemented.sh`, exit 3),
so **no instance is enabled by default**. The target itself may be
enabled (it is empty until instances are added). Enable per instance
as backends land, e.g.:

```
systemctl enable squeezebox-source@spotify.service
```

Trial start without enabling: `systemctl start squeezebox-source@radio`
(fails honestly today: adapter exits 1, backend exit 3, arbiter and
Now Playing untouched — see `docs/test-results/wp2-standalone.md`).

## Ordering

Instances run `After=squeezeplay.service sound.target network.target`:
Jive owns the UI/audio first; standalone sources are additive. The
audio arbiter (`/usr/sbin/audio-owner`, Agent 3) serializes ALSA
access at runtime regardless of start order.

## Validation (host, WP2)

- `bash -n` over all shipped scripts: clean.
- `systemd-analyze verify` on the units with target paths rewritten
  to a staging dir: clean (see `docs/test-results/wp2-standalone.md`).
- Full adapter lifecycle against the real arbiter:
  `standalone/tests/test-arbiter-integration.sh` (43/43 on host).
