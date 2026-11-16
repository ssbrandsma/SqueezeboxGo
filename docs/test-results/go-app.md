# go-app — SqueezeboxGo App Center package test results

Date: 2026-11-16. Branch: `go/app-package` (isolated worktree, base main
`b6d4cfd`). Host-only: no device touched (no ssh); every claim below was
observed on this machine.

Owner note: `docs/test-results/` is Agent 6's tree; this file is the
GO-APP evidence deliverable per the workflow task.

## Summary

All five GO-APP tasks complete and host-verified:

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | 160x120 RGBA icon | PASS | `file` + IHDR parse + viewed render + determinism |
| 2 | Jive Return-to-Anbernic action (`SQUEEZEBOX_GO=1` gate, cleanup, exit 42) | PASS | luac-5.1 clean + host execution harness (4 modes, 36 checks) |
| 3 | `pack.sh` reproducible ZIP + lifecycle scripts | PASS | device ZIP built (24.7 MB), rebuild-twice identical, payload verified |
| 4 | INSTALL.md + UNINSTALL.md | PASS | idempotent install/upgrade + reversible removal drilled on host |
| 5 | committed tests + recorded results | PASS | `squeezebox-go/tests/` suite: 62/62, exit 0 |

Totals — PASS: 62, FAIL: 0, NOT RUN: 0 (in-suite skips: 0).
Honest non-results: real `shellcheck` absent on host (bash -n fallback
used — see §5); device behaviors (icon visibility, button nav, audio
ears, frontend unit name) are GO-HW/human-gated.

## 1. Icon (task 1) — PASS

Generator: `squeezebox-go/icon/make-icon.py` (stdlib-only: struct+zlib;
no Pillow on host). Git stays text-only: the PNG is generated at pack
time, never committed.

Observed:

```text
$ python3 make-icon.py -o /tmp/sbgo-icon.png
wrote /tmp/sbgo-icon.png (1965 bytes, 160x120 RGBA)
$ file /tmp/sbgo-icon.png
PNG image data, 160 x 120, 8-bit/color RGBA, non-interlaced
$ python3 IHDR-parse
IHDR: 160 120 bitdepth 8 colortype 6
OK: 160x120 RGBA
```

- Render inspected visually: orange handheld slab with EQ-bar display,
  play triangle, control dots, speaker + wave arcs on dark navy —
  high-contrast, readable at thumbnail size.
- Determinism: two runs byte-identical
  (sha256 `261f7cc4…05d0e7`, `cmp` clean).

## 2. Jive action (task 2) — PASS

Files (shared tree, fork-free):

- `squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH/
  SqueezeboxRG35XXHMeta.lua` — registers home item
  `appletGoReturnToFrontend` (node `home`, weight 1009, just above the
  desktop Quit item at 1010) ONLY when `SQUEEZEBOX_GO=1`.
- `.../SqueezeboxRG35XXHApplet.lua` — `returnToFrontend()`: storeSettings
  → `disconnectPlayer` service → `Decode:stop()` (guarded by the
  `_decodeOpen` flag set at init) → restore helper
  (`$SQUEEZEBOX_GO_RESTORE`, fallback `$SQUEEZEBOX_GO_ROOT/restore.sh`,
  `--from-jive`) → unconditional `os.exit(42)`. Every step is
  `pcall` + log; `Framework:quit()` cannot carry a code (always exit 0
  via JiveMain — verified in `JiveMain.lua`), hence `os.exit`.
- `.../strings.txt` — `GO_RETURN_TO_ANBERNIC` / `Return to Anbernic`.
- Hardening in the same files: `require("rg35xxh_bsp")` is now
  `pcall` (the App Center payload ships Lua only; without this the
  applet — and the menu item — could never load on device). The C
  module is side-effect-only (uevent pump), so `nil` is safe.

API grounding (all read in the pinned `758bc11` tree at
`/tmp/jammy-sp/squeezeplay/src`):

- Menu pattern: desktop `Quit/QuitMeta.lua` (`jiveMain:addItem`, node
  `home`, weight 1010, `disconnectPlayer` + quit in callback);
  `menuItem(id, node, label, closure, weight)` helper in
  `jive/AppletMeta.lua`; `HomeMenu:addItem` requires `id` + `node`.
- `decode:stop()` (no args) is the `Playback.lua` convention;
  `decode.c` exposes `open/stop/flush/...` (no `close`); process exit
  releases all fds/children.
- No store-all API exists (`AppletManager._storeSettings` takes a
  private entry; Jive persists per-applet) — the action stores our
  applet's settings, documented in code + README.

Observed:

```text
$ luac5.1 -p SqueezeboxRG35XXHApplet.lua SqueezeboxRG35XXHMeta.lua loadPriority.lua
LUAC-CLEAN
```

Host execution harness (`squeezebox-go/tests/test-jive-action.lua`,
lua5.1, stub framework via `package.preload`, loads the REAL applet
files): gate-off registers nothing (B, 3 checks), gate-on registers
id/node/weight/text and the callback runs
store < disconnect < decode-stop < exec-restore < exit-42 in order (A,
15 checks), `$ROOT/restore.sh` fallback (A2, 14 checks), decode-failed
skips stop but still exits 42 (D), missing `.so` tolerated (C):

```text
PASS (B/C)   PASS (A)   PASS (A) [A2]   PASS (A/D)
```

## 3. Packaging + lifecycle (task 3) — PASS

`pack.sh` builds `SqueezeboxGo-<ver>-stockos-rg35xxh.zip` (default
`--output squeezebox-go/dist/`, `--version` from `VERSION`,
`--epoch` = CLI > `SOURCE_DATE_EPOCH` > last commit time > fixed
fallback; `--fixture` for artifact-free test builds).

Device build observed (real artifacts on this host):

```text
$ ./squeezebox-go/pack.sh --output /tmp/sbgo-real1 --epoch 1767225600
pack.sh: mode=device version=0.1.0 epoch=1767225600
pack.sh: wrote .../SqueezeboxGo-0.1.0-stockos-rg35xxh.zip
  (24742078 bytes, sha256 dfdb9cdb…498d80)
pack.sh: payload jammy=673ec5ee…02baa fbcon=3924a625…3f8d4a
```

Both input hashes match the recorded known-good values
(`diag-jammy-build.md`, `sdl-fbcon-build.md`). ZIP contents verified:
5 FAT entries, no symlinks, `SHA256SUMS` verifies, icon 160x120 RGBA;
payload extracts to `MANIFEST/VERSION/config/jive/launch.sh/
lib-fbcon/restore.sh`, jive is `ELF 64-bit ARM aarch64`, fbcon
`libSDL-1.2.so.0` present, both overlays present
(`SqueezeboxRG35XXH/` with `returnToFrontend`, `RG35XXHBaseSkin/`),
tar has fixed 0/0 uid/gid + mtime. Fixture ZIP rebuild-twice:
identical sha256 (`58b8feeb…bdbf4`, `cmp` clean).

Lifecycle observed on host (fixture payload, fake Roms + fake root):

- entry installs with hash check → launch claims state → jive(42) →
  "Return to Anbernic (clean)" → restore runs → exit 0.
- idempotent re-run skips install, exit 0; corrupt payload refused
  (`hash mismatch`); crash path (jive exit 1) still restores, exit 0;
  SIGTERM drill: `got SIGTERM`, jive child reaped, cleanup ran,
  exit 143, no stray processes.
- Two bugs found by these drills and fixed: `exec systemd-run`
  fallback unreachable (now probe-then-re-exec), doubled log levels.

Scripts: `bash -n` clean (5/5) + `sh -n` POSIX-clean entry; repo lint
gate verdict via identical copies (the gate prunes `*/.muse/*`
worktree paths): PASS on `bash -n` fallback (shellcheck not
installed — see §5).

## 4. Docs (task 4) — PASS

- `squeezebox-go/INSTALL.md`: download → verify → extract to `Roms/` →
  App Center launch → Return flow + troubleshooting table.
- `squeezebox-go/UNINSTALL.md`: the only three write locations, SSH +
  card-only removal, verify + reinstall notes.
- `squeezebox-go/README.md`: mechanism, ZIP layout, exit-code contract
  table, env contract table, frontend-claim strategy, state map, known
  limitations, never-list.
- Idempotence (reinstall skip, version-gated upgrade) and reversibility
  (hash-guarded install, corrupt refusal, complete removal paths)
  demonstrated by the drills in §3.

## 5. Suite (task 5) — PASS (62/62)

```text
$ bash squeezebox-go/tests/test-package.sh
[go-app] totals: 62 pass, 0 fail, 0 skip
[RESULT] go-app-package: PASS   (exit 0)
```

Covers: files present (19), icon file+IHDR+determinism (4),
no-secrets grep (1), bash -n ×5 + sh -n + lint gate (7), luac ×4,
Lua harness ×4 modes, fixture ZIP list/symlinks/ASCII/case/SHA256/
payload-content ×14 + reproducibility, device build + aarch64 ELF (2),
entry install/idempotence/corrupt-refusal (3).

Non-result (honest): `shellcheck` is not installed on this host
(`command -v` empty, standard PATH dirs checked); the gate's `bash -n`
fallback ran instead and passed. Scripts are written to
shellcheck-clean idioms (quoted expansions, no backticks, narrow
`SC2086` disables for intentional word-splitting). Re-run the suite on
a host with shellcheck for the full verdict.

## Device-gated follow-ups (for GO-HW / human)

- Frontend unit name per stock image; whether App Center suspends
  dmenu (may flip `SQUEEZEBOX_GO_NO_FRONTEND_STOP` to default-on);
  cgroup placement of APPS scripts (escape probe covers both).
- Human-gated: icon/menu visibility, button navigation (evdev2jive NOT
  in this package), audio ears, game-after-exit check.
- Skin first-run selection with the shipped `RG35XXHBaseSkin`.
