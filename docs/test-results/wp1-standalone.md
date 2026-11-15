# WP1 Standalone test results (2026-11-15, branch `wp1/standalone`)

Owner: Agent 5. Cross-tree note: this file lives in Agent 6's
`docs/test-results/` tree; written here because the WP1 task explicitly
requires Standalone evidence at this path.

## 1. Source survey (task 1) — method + verdict

Swept `/home/sjoerd` (maxdepth 4-6 `find -iname` for `*standalone*
*nowplay* *now-play* *qobuz* *spotify* *librespot* *fab4* *tinysc*
*tinylms* *squeezeplay* *squeezelite* *squeezeslave* *vpn* *openvpn*
*wireguard*`, excluding caches/vendored buildroots) plus the workspace.

- FOUND, real, version 9.0.2: NowPlaying applet + `jive/slim`
  Player/SlimServer/ArtworkCache APIs (4 identical trees:
  `~/squeeze_userbuild/source/src`, `~/jive-{performance-source,
  partial-rotation-offline, render-diag}-20261024/src`; NowPlaying md5
  `08a4bf2d00953c57189d5cf609c05f68` in all four); Baby + Fab4 +
  SqueezeOS device applet sets; `meta-squeezeos` recipes incl.
  `openvpn_2.5.11` and `squeezelite_2.0.0`; SCM pins
  `squeezeos-squeezeplay;branch=public/9.0` and `slimserver;tag=9.0.2`.
- MISSING everywhere: Spotify/Qobuz/Radio/Music service backends
  (Jive tree has only the `ChooseMusicSource` shell; `libspotify`
  recipe points at a private SVN; `squeezify-build` holds librespot
  cargo fingerprints only, zero `.rs` sources); device-local web UI;
  proxy; device-side VPN integration (`tun.ko-*` blobs referenced but
  absent, 2.6-era, unusable). `StandaloneBase/` in the radio device
  backup holds one `.ko` only — a name false-friend.
- Full found-vs-missing table with exact paths and vendoring pins:
  `standalone/REQUIRED_SOURCES.md`.

## 2. Static checks — observed

- `sh -n` over `standalone/base/*.sh`,
  `standalone/integration/*.sh`,
  `standalone/integration/services/*/backend.conf`: **all clean**.
- `luac -p standalone/integration/bsp-shim.lua` (PUC Lua 5.1.5,
  matching the arch pin): **clean**; `loadfile` assert: **ok**.
- shellcheck: not installed in this environment — not run.

## 3. Functional tests (all in `/tmp/wp1-sa-test`, stub arbiter) — observed

- Adapter lifecycle `demo start/status/stop` with `/bin/sleep 120`
  backend: started pid 17835, status reported running, stop reaped it
  (`pgrep` confirms no survivor); arbiter log order exactly
  `acquire demo` / `release demo`; start published
  `source_id=demo,mode=play,power=true`, stop published `mode=stop`.
- `nowplaying-pub.sh`: full 23-key state validates under
  `python3 json.load`; adversarial values (`Comma, "Quote" \ Backslash`,
  `Last, First`, `hw:0,0`) survive byte-identical across 3 merge
  round-trips; single-key update preserves all other keys; unknown key,
  non-numeric volume, non-boolean power each exit 1 with a message.
- `web-routes.sh list`: merged table correct incl. `(src=...)` tags and
  `# no routes.conf` for proxy; `FETCH` method rejected, exit 1.
- `unimplemented.sh` stub backend: prints reason, **exit 3**.
- `bsp-shim.lua` via `require` (stub `loop.simple`): `getDisplaySize`
  returns `640, 480`; all 7 HAL-backed functions raise
  `UNIMPLEMENTED: bsp-shim.<fn> needs rg35xxh_bsp.<slot>`.
- Two bugs found and fixed during testing: adapter `publish` dropped
  its `shift 3` (fixed, re-tested); publisher stripped commas inside
  values and mis-merged quoted strings (rewrote with S:/N: tagged
  values, re-tested incl. adversarial round-trips).

## 4. Not covered (needs other agents / WP3)

- Real `audio-owner` arbiter (Agent 3) — stub used; client shells out
  per contract only.
- Real backends (librespot, slimserver plugins, web server, VPN) —
  UNIMPLEMENTED stubs with contracts, pending source vendoring.
- On-target run (aarch64 image does not exist yet in WP1).
