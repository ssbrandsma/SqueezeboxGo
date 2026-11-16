# dd1 — Jive log lines for the display investigation
# Status: PROVISIONAL-build lines transcribed (same jive binary 4649e37a +
# same SDL 3924a625 as final — SDL/video behavior identical); FINAL-build
# lines need a menu run with buttons (human-session item H-LOG below).

## Transcribed 2026-11-16 15:10 CET from /opt/squeezebox-go/logs/jive.log
## (owner's 14:39 menu run, old build; file destroyed by the upgrade rm -rf)

```text
semget: Function not implemented
semctl: Function not implemented
... SqueezePlay version 9.0.0 r541
... jiveL_initSDL:239 initSDL
... jiveL_initSDL:252 640,480 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]
... jiveL_initSDL:253 Hardware acceleration is available
... jiveL_initSDL:254 Window Manager is not available
... jiveL_initSDL:257 Using 22 frames per second
... ERROR ... Can't find image jive/splash640x480.png
... jive_surface_set_video_mode:860 Window Manager is not available
... jive_surface_set_video_mode:861 Video Setup for fullscreen
... jive_surface_set_video_mode:910 Video mode: 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]
... jiveL_initSDL:330 Splash jive/splash.png 480x272 Screen 640x480
... Registering action: soft_reset with index: 1
... locale parsing ... (DEBUG volume from button input)
```

Reading for lead: exactly ONE `Video mode:` line in the head-40 window
(full-file count unavailable — file gone); screen 640x480; requesting
bpp is 16 at the SDL call (per lead's source trace) but the NEGOTIATED
surface is 32-bit XRGB (R<<16 G<<8 B<<0) — the driver upgraded 16→32.
Splash line present (480x272 onto 640x480 screen). SDL video driver
NAME line not in the transcribed window; ctypes probe reports
driver=b'fbcon' (dd3). Skin-selection lines not in the transcribed
window (needed: see H-LOG).

## Why no headless final-build log exists (proven, both trees)

Seven headless runs (12 s–6 min, old/new tree, ±overlay, ±stdbuf -oL)
emit ZERO logger lines: jive block-buffers stdout (large buffer,
self-setvbuf suspected — stdbuf is overridden) and the SIGTERM/quit
path exits WITHOUT flushing (post-exit files gain nothing). The
owner's session was chatty only because 33 min of BUTTON input
produced the DEBUG volume that flushed the buffer mid-run. No CLI
verbosity flag exists (jive.c passes argv[1] to require() — `jive
--help` → module-not-found traceback; C logger level API is
log_category_set_priority, reachable only from code/settings).

## H-LOG (human session): menu run + navigate ~1 min, then the agent reads
# Preconditions: device awake, SqueezeboxGo 0.1.0 installed (done),
# owner at the device with eyes + fingers.
# 1. Owner: App Center → SqueezeboxGo; wait for first frame (~20-40 s);
#    navigate the language menu with pad/USB-kbd for ~1 min (any keys).
# 2. Agent (SSH): `tr -d '\000' </dev/shm/squeezebox-go/logs/jive.log |
#    grep -a -c 'Video mode:'` (1 = no switch, 2 = skin re-set the mode),
#    plus `grep -a -E 'Video mode|Splash |Skin|skin|setVideoMode|Cannot be
#    reused|SqueezeboxRG35XXH|GO_RETURN'` — full lines to this file.
# 3. Owner: Return to Anbernic → confirm dmenu return without reboot.
