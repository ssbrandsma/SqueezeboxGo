# HW go-redeploy report — 2026-11-16 (ANBERNIC, live SSH)
# Agent: HW go-redeploy, branch hw/go-redeploy (from 3ba37ff + main merge).
# End state: SqueezeboxGo 0.1.0 cleanly installed; device last seen
# stock-healthy (dmenu 8939, vinfo stock, stock pixels) at ~15:55 CET,
# then unreachable (ping-dead) mid core-forensics window → BLOCKED-on-wake
# for the final 3 device steps (see §blocked). dmenu was STOPPED at
# blackout — owner must power-press to wake (short press, no hold).

## 1. Install state: DONE (final ZIP, INSTALL.md user path)

- Host sha: 99c28329… ✓ (matches brief); on-device sha after scp:
  99c28329… ✓. Payload: VERSION 0.1.0, payload hash dafdbbf0… OK,
  3430 files incl. applet overlay (Meta/Applet/strings with
  GO_RETURN_TO_ANBERNIC), RG35XXHBaseSkin, launch.sh, restore.sh,
  lib-fbcon.
- `unzip -o APPS/*` onto /mnt/mmc/Roms/APPS: icon 240x180 RGBA sha
  0b7b721c (provisional 8513a16d OVERWRITTEN ✓), entry sha 05b8e6b7
  ✓, `sh -n` OK. First launch upgraded /opt/squeezebox-go
  (0.1.0-go1 → 0.1.0, hash-verified); second launch took the
  skip-install path (`runtime 0.1.0 present; skipping install` ✓).
- stock/go/install-squeezebox-go.sh NOT used: it installs the
  SUPERSEDED provisional layout and would regress entry+icon.
  Follow-up: update or retire it (lead/GO-APP).
- Evidence: docs/hw-evidence/go-redeploy-preflight.txt,
  go-redeploy-install.txt.

## 2. Lifecycle result: DONE headless (exit-42 E2E needs fingers)

- Entry path reproduced byte-exact (`/tmp/.next` 39 B + `sh`
  /tmp/.next as root). Documented deltas vs true menu path: parent
  is the SSH shell (not dmenu_ln), stdout captured (not /dev/null).
- Run 1 (dmenu alive): cgroup escape → scope → frontend stop →
  mixer/fb snapshot → jive 6 min healthy. DOUBLE-RUN RACE (repro
  artifact, diagnosed to high confidence): stop SIGTERMs dmenu
  with .next present → dmenu exits 0 → dying dmenu_ln runs
  `sh $ACT` once (B's env proves dmenu_ln parentage). Shared-state
  fallout: B truncated A's jive.log, deleted the frontend stamp
  (no auto-restart), SEGV'd in dual-jive contention (exit 139 —
  artifact, 7 solo runs since, zero SEGV). Product impact: none
  (dmenu is dead in the real menu flow). New SSH rule: `rm -f
  /tmp/.next` before stopping the frontend; GO-APP follow-up:
  entry/launch.sh could do it.
- Run 2 (pre-stopped, no .next): clean single run, skip-install,
  inactive-frontend path, jive 6+ min healthy (idle CPU, fonts,
  stable frame, settings). SIGTERM → jive exit 0 → UNEXPECTED
  branch → restore → manual frontend start → stock.
- Installed-action probe ON DEVICE (harness via `jive <module>`
  against installed files, device Lua 5.1): PASS (A) 15/15 incl.
  exit code 42 + restore.sh --from-jive, PASS (A/D), PASS (B/C).
  Gotcha fixed in device copy: clear package.loaded so stubs win.
- launch.sh contract ON DEVICE (real script, stub jive): exit 42
  → `Return to Anbernic (clean)` + restore + exit 0; exit 0 →
  UNEXPECTED + restore + exit 0. (Scratch runs share $STATE:
  stamp backed up/restored; first muse-run showed launch.sh
  degrades to stdout when the log dir is unwritable.)
- Logger silence (both trees, 7 runs): idle jive never emits
  logger lines (big block-buffered stdout + no-flush quit path);
  the owner's session was chatty only via button-driven DEBUG
  volume. Proposal: `stdbuf -o0` around jive (untested) or document.
- sem-spam bimodal (~20/s vs ~0.2/s, both trees): audio-path race
  for the audio agent. First-frame latency >18 s (drawn by ~22–44 s).
- Input: uinput AT-keyboard taps (ENTER/DOWN/UP/ESC ×2 runs) NEVER
  moved the fb hash — headless jive is INPUT-DEAF (SDL1.2-fbcon
  VT keyboard needs a console; BTN_* lack VT keysyms anyway).
  → Physical exit-42 traversal is HUMAN-QUEUED (H-EXIT below);
  every surrounding link is device-proven.
- Evidence: docs/hw-evidence/go-redeploy-lifecycle.txt.

## 3. Display-debug (lead add-ons): captured + queued

- dd1: provisional `Video mode: 32 bits/pixel … [R<<16 G<<8 B<<0]`
  line transcribed (16-bpp request NEGOTIATED to 32-bit XRGB);
  screen 640x480; driver=fbcon (ctypes probe). Final-build lines
  need H-LOG. No CLI verbosity flag exists (argv→require()).
- dd2: stock vinfo fully dumped (1280x1024x16, pixclock 9369,
  margins 224/32/32/4, sync 136/4, zeroed bitfields); stuck
  menagerie (4 geometries); during-jive (pre-frame): unchanged.
  PUT-restore recipe proven 3x (vinfo-full.py put-stock).
- dd3: bare SDL_SetVideoMode(640,480,16,FULLSCREEN) headless:
  init fails without SDL_NOMOUSE=1 (no /dev/input/mice); with it,
  init OK then SetVideoMode HANGS (no return 4+ min, no PUT
  landed; orphans kill -9'd). Jive's own PUT succeeds → its call
  differs (flags/env — confirm from jive_surface.c). Hang site
  unproven (VT_WAITACTIVE suspected; re-hang needs nohup+disown).
- dd4: DE `sys` stock (mgr0 640x480, NO BUF line, full dump) vs
  during-jive (EXTRA `BUF enable ch[1] lyr[0] … fb[640,480]`
  layer line) — delta REAL (rechecked full). dispdbg BLOCKED
  (`cat info` = 62 MB NUL flood; needs vendor protocol).
- dd5: splash = C jiveL_initSDL blit of 480x272 RGB splash.png
  (only splash asset; drawn on stock vinfo → correct); menu =
  640x480x32 surface through a stuck mode (stride/format skew →
  torn). Skin identity (RG35XXH vs WQVGA fallback) needs H-LOG.
- Outstanding: vinfo at first-flip vs menu-settled (flip-poll was
  mid-run at blackout), core-dump logger forensics (§blocked),
  display-trial.py unattended run (§blocked — pulled, unread on
  device work yet).
- Evidence: docs/hw-evidence/display-debug/{00-summary,dd1..dd5}.md.

## 4. Staged for the human session (all verified, none run)

- evtest LIVE capture: evtest present, both by-path nodes resolve,
  --query rc=0 (timeout 5, no grab). Exact owner script + expected
  first-lines: docs/hw-evidence/go-evtest-live.md. (Also feeds the
  mapper-gap diagnosis: record EVERY event2 code.)
- Color-fill live run: /tmp/color-fill.py on device (sha
  666befe1, COMPILE_OK, usage rc=2), sudo + fb0-RW proven. Exact
  two-shell command: docs/hw-evidence/go-colorfill-staged.md
  (re-scp if /tmp was wiped).

## 5. Human-ask list (preconditions first)

Preconditions for ALL: device awake (power-press if dark — it may
have slept with dmenu stopped, or the battery sagged; if it boot-loops
or stays dark, STOP and report), SSH `rg35xxh` answers, `pidof
dmenu.bin` non-empty (else `sudo -n systemctl start
launcher.service` first — agent step on wake).

- H-OBSERVE (no precondition beyond awake): what did the LCD show
  during the 14:39–15:12 provisional menu session (icon? Jive UI?
  buttons? sound?)? And the CURRENT Jive language-screen
  corruption (photo if possible — already partially reported).
- H-LOG (SqueezeboxGo installed ✓): App Center → SqueezeboxGo,
  wait ~20–40 s for first frame, navigate ~1 min (any keys),
  leave it running; agent then reads /dev/shm/.../jive.log
  (`Video mode:` COUNT (1 vs 2), Splash/Skin/setVideoMode lines).
- H-EXIT (after H-LOG): home menu → Return to Anbernic; report
  frontend return WITHOUT reboot (+ any LCD anomaly). WATCH: if
  jive ever vanishes/crashes SOLO (no SSH run active), note exact
  time + what was on screen (flaky-SEGV watch).
- H-INPUT (anytime in jive): do pad buttons do ANYTHING? Try USB
  keyboard if available (diagnostic control). Try evtest capture
  (§4) in parallel if fingers allow.
- H-COLOR (after H-EXIT, dmenu alive): coordinated color-fill run
  (§4) — watcher + operator.
- H-GAME (after H-EXIT): launch any game, confirm saves intact.

## 6. Blocked-on-wake (device ping-dead since ~15:58 CET) + resume

Left state at blackout: dmenu STOPPED (display window), jive 9179
(timeout-150, likely expired cleanly), vinfo stock, fb leftover,
/dev/shm logs + /tmp scratch (probe scripts, sbgo-upload.zip 24 MB,
oldtree extract, cores if any) intact IF no reboot/power-loss.
Candidates: mem-suspend with dmenu dead (would be NEW — suspend
without the dmenu timer!), WiFi drop, owner power-off, battery sag.

- R-WAKE: owner short-presses POWER (no hold); agent re-probes SSH.
- R-TRIAGE: `pidof dmenu.bin jive; systemctl is-active
  launcher.service; vinfo-full.py get | head; fbhash.py;
  ls -la /tmp/core* /dev/shm/squeezebox-go/logs/` → decide:
  resume window (dmenu dead, logs alive) vs fresh stock.
- R-FORENSICS (if logs alive): strings-grep the jive core (if
  ABRT landed): `Video mode` count, Splash/Skin/setVideoMode
  lines → dd1/dd5. Else re-run the flip-poll + ABRT (fixed sha
  compare: `cut -d' ' -f4`).
- R-TRIAL (ON HOLD — 3 bugs found in review, flagged to lead, NOT
  run): stock/bundle/display-trial.py as committed cannot run the
  matrix on device: (1) put_var packs VAR_FMT "8I12I4I" (24 items)
  against 36 VAR_NAMES → struct.error on EVERY PUT (uncaught —
  only OSError is caught); PUT needs the full 40×u32 layout
  (reference: vinfo-full.py put-stock, proven 3x on device);
  (2) blit() calls mm.flush() → EINVAL OSError on fb0 mmap
  (phase-3 quirk, uncaught in blit); (3) stride assumes packed
  xres*bpp/8 while the driver reports line_length 2560 (use
  FBIOGET_FSCREENINFO 0x4602, currently defined but unused).
  As-is it would draw attempt 1, then traceback with a scary
  (but harmless — nothing was PUT) RESTORE-FAILED line. AFTER
  lead fixes: scp to device; `sudo python3 display-trial.py
  --hold 2 --rounds 1` UNATTENDED (dmenu stopped first, .next
  removed); commit log to display-debug/. Stopgap option: the
  same PUT matrix via vinfo-full.py (correct layout) if the fix
  is delayed.
- R-GATE (last): secure /dev/shm logs to host (scp), commit,
  `sudo reboot`, re-verify (dmenu boot-hold? vinfo stock? VT
  tty1-vs-tty2? no strays?), append to this file, clean /tmp.
