# Display-debug evidence (lead add-on) — 2026-11-16, ANBERNIC live SSH
# Owner report: Jive language screen VISIBLE on LCD but CORRUPTED
# (recognizable text + multicolour artifacts, black regions, vertical
# line near right edge, alternating scanlines, not filling 640x480).
# The C boot splash (Lyrion splash.png) renders CORRECTLY; the menu
# path corrupts. Same jive binary (4649e37a) + SDL (3924a625) in
# provisional and final builds, so all findings apply to both.

## dd1 — Jive log lines (transcribed from the 14:39 provisional menu run;
## /opt log destroyed by the upgrade rm -rf; final-build lines need a
## menu run with buttons — human-session item, see dd1-log-lines.md)
# ... SqueezePlay version 9.0.0 r541
# ... jiveL_initSDL:239 initSDL
# ... jiveL_initSDL:252 640,480 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]
# ... jiveL_initSDL:253 Hardware acceleration is available
# ... jiveL_initSDL:254 Window Manager is not available
# ... jiveL_initSDL:257 Using 22 frames per second
# ... ERROR ... Can't find image jive/splash640x480.png   (benign, fallback)
# ... jive_surface_set_video_mode:860 Window Manager is not available
# ... jive_surface_set_video_mode:861 Video Setup for fullscreen
# ... jive_surface_set_video_mode:910 Video mode: 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]
# ... jiveL_initSDL:330 Splash jive/splash.png 480x272 Screen 640x480
# SDL video driver name: NOT in transcription; ctypes probe reports
# driver=b'fbcon' (see dd3-sdl-probe.txt). Screen w/h = 640x480.

## dd2 — fb state (see dd2-fb-stock.txt / dd2-fb-during-jive.txt)
# STOCK (dmenu 8188): vinfo 1280x1024x16 virt=1280x1024, zeroed
# bitfields, pixclock 9369, margins 224/32/32/4, sync 136/4;
# sysfs virtual_size 1280,1024 bpp 16 stride 2560, mode EMPTY
# (always), pan 0,0 rotate 0 state 0; fb0 sha 6de7493c…
# (phase-3's exact stock pixels).
# DURING headless jive (8587, 18 s): vinfo UNCHANGED stock, fb
# UNCHANGED stock pixels (no first frame yet — latency >18 s;
# input-probe runs drew between t+22 and t+44).
# STUCK MENAGERIE this session (PUT quirk, nondeterministic):
# 512,384-virtual (owner run), 320x240x16 (run-2), 512x384x32
# (input probe + dmenu-7829 boot), full stuck dump: bitfields
# zeroed, pixclock 49603, margins 48/16/16/1, sync 64/3.
# fbset: NOT on stock (all readings via sysfs + ioctl).

## dd3 — SDL probe (see dd3-sdl-probe.txt)
# ctypes call of SDL_SetVideoMode(640,480,16,FULLSCREEN) with the
# payload fbcon lib: SDL_Init(VIDEO) FAILS without SDL_NOMOUSE=1
# (`Unable to open mouse` — no /dev/input/mice on stock; jive must
# set NOMOUSE itself or pass other flags); with NOMOUSE=1: rc=0,
# driver=fbcon, then SetVideoMode HANGS headless (blocking ioctl —
# likely VT_WAITACTIVE with no console VT; jive's own PUT succeeds
# headless, so its call path differs — flags/env TBD from source).

## dd4 — DE layer state (see dd4-de.txt)
# STOCK: attr xres/yres = 640/480; `sys`: mgr0 640x480 fmt[rgb]
# lcd 640x480 @59.8 backlight 140, dmabuf cache[4], NO BUF line
# (head -8 — full-dump comparison still open, see below).
# DURING jive: mgr0 identical; dmabuf cache[6]; BUF line PRESENT:
# `enable ch[1] lyr[0] z[20] ... fmt[10] fb[640,480] crop[0,0,640,480]
# frame[0,0,640,480] addr[ff600000,ff64b000,ff696000]`.
# Caveat: stock side was captured with `head -8` — the BUF line may
# have been truncated, not absent. RECAPTURE full stock `sys` before
# claiming a layer delta.
# dispdbg (/sys/kernel/debug/dispdbg): BLOCKED — `cat info` spews
# ~62 MB of NUL-padded binary (no text protocol); abandoned without
# the vendor command protocol (reads only, device unharmed).
# boot_para: disp_para=100 init_disp=0 tv_vdid=0 fb_base=0x0
# disp_config0=1,0 - 0,0,260,4 disp_config1=2,11 - 1,0,260,4.

## dd5 — splash vs menu path (see dd5-splash.md)
# C boot splash: jiveL_initSDL loads jive/splash.png (480x272 RGB
# PNG, 7661 B — the ONLY splash file; splash640x480.png absent) and
# blits it DIRECTLY (pre-main-loop) — renders CORRECTLY (owner).
# Lua splash window: JiveMain.lua:385-400 (2 s timer, key-dismiss).
# Menu path: SDL 640x480x32 surface + skin setVideoMode + SDL blits
# through the STUCK vinfo (pitch/format mismatch) — corrupted.
# Differential hypothesis for UI/agent-2: splash draws while vinfo
# is still STOCK (early boot); the menu re-negotiates the mode
# (zeroed-timings PUT → sticky geometry) and renders into a
# surface whose pitch/format no longer matches the scanout —
# alternating scanlines + unfilled 640x480 fit a stride mismatch;
# multicolour artifacts + vertical line fit a format/offset skew.
# Requested next evidence (human session): menu-run jive.log
# (Video mode line + driver + skin lines) + photo of corruption.

## Tooling committed with this evidence
# /tmp on device (scratch, NOT committed): vinfo-full.py (get +
# put-stock valid-timings recipe), fbhash.py, sdl-probe.py,
# sbgo-uinput.py, sbgo-probe/probe.lua (device copy of the GO-APP
# harness + package.loaded clearing).
# Proposed for repo (GO-APP/UI follow-up, not added here):
# stdbuf -o0 around jive in launch.sh (headless log visibility),
# `rm -f /tmp/.next` before frontend stop (double-run race),
# package.loaded clearing in test-jive-action.lua.
