# Splash service hooks (for Agent 1 Platform)

`init-splash.sh show` paints `splash_640x480.png` via `drm_splash`
(raw DRM ioctls, no libdrm/X/plymouth dependency) and holds DRM master
(PID in `/run/splash.pid`) until `init-splash.sh stop` (SIGTERM) or the
process is killed. No animation: one static frame from ~1s into boot
until Jive's first frame.

## Files to install

| File (this tree) | Target path |
|---|---|
| `ui/splash/init-splash.sh` | `/opt/squeezeplay/bin/init-splash.sh` (or `/usr/sbin`) |
| `ui/splash/drm_splash` (built) | `/opt/squeezeplay/bin/drm_splash` |
| `ui/splash/splash_640x480.png` | `/usr/share/squeezebox/splash_640x480.png` |

`drm_splash` build (target, Agent 2 toolchain):

```sh
$CC $CFLAGS -o drm_splash drm_splash.c pngmini.c blit.c -lz
```

Env overrides (no rebuild to retune): `BIN_DIR`, `PNG`, `CARD`, `PIDFILE`.

## Suggested units (platform owns the files, snippets only)

Early painter — after the GPU/DRM device appears, before squeezeplay:

```ini
[Unit]
Description=Squeezebox boot splash
DefaultDependencies=no
After=systemd-udev-settle.service
Before=squeezeplay.service
ConditionPathExists=/dev/dri/card0

[Service]
Type=forking
PIDFile=/run/splash.pid
ExecStart=/opt/squeezeplay/bin/init-splash.sh show
ExecStop=/opt/squeezeplay/bin/init-splash.sh stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Handoff — stop the splash when Jive is up. Simplest: in
`squeezeplay.service`, `ExecStartPre=-/opt/squeezeplay/bin/init-splash.sh stop`
(the `-` tolerates "already gone"). SDL/KMSDRM then becomes DRM master and
paints the skin; no blank gap beyond one modeset.

## Failure behavior (by design)

- No `/dev/dri/card0` yet → script exits 1, boot continues, Jive paints
  when it starts. Never blocks boot (`Type=forking` + no `Requires`).
- `drm_splash` holds forever until SIGTERM; if squeezeplay fails to start,
  the splash stays up (preferred over a black screen) and the unit can be
  stopped manually.
- `--timeout SECS` exists on `drm_splash` if the platform prefers a
  self-expiring splash; not wired by default.
