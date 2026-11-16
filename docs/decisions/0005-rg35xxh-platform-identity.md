# ADR-0005 — Platform identity: `rg35xxh`

Date: 2026-11-16. Status: accepted (user-confirmed live).

## Context

Jive advertises its platform in three places: `System:getMachine()`
(C global, default `"squeezeplay"`), `LocalPlayer` device id/model/name
(defaults 12/`"squeezeplay"`), and the applet-repository query
(`SetupAppletInstaller` sends `target:<machine>`). On the RG35XX H
stock PoC (desktop-config build), all three said `squeezeplay`, so the
applet repo served nothing and the server/discovery side could not
tell the device apart. The user will build Standalone Base, Spotify
Connect, and applets per-platform and asked for a baby/fab4-style
platform name.

## Decision

The canonical platform identity is **`rg35xxh`**, used consistently
for the machine name, the player device type/model, the applet-repo
target, and (later) firmware filenames:

- `System:init({ ..., machine = "rg35xxh" })`
- `LocalPlayer:setDeviceType("rg35xxh", "Squeezebox RG35XX H")`
  (device id 9, same fab4-pattern choice as the `SqueezeboxRG35XXH`
  BSP meta, which already used this pair)
- Applet query asks `target:rg35xxh` first, falls back to `target:baby`
  while the repo has no platform entries (most baby applets are pure
  Lua and run unmodified), then to squeezenetwork as before.

The stock-PoC patch (vs `ralph-irving/squeezeplay@758bc11`, both files
verified byte-identical to the pin before patching) lives at
`stock/bundle/rg35xxh-identity.patch`, covered by
`stock/tests/test-rg35xxh-identity.sh` (patch markers + mirrored
fallback behavior under PUC Lua 5.1.5).

## Consequences

- HELO now carries id 9 / model `rg35xxh` (verified live: session to
  the bootstrap server built after the patch).
- Udap responses (when server-unconnected) and the HTTP user-agent
  carry the new identity; `stock/tests/udap_probe.py` solicits and
  decodes them for future checks.
- The SlimServer firmware-upgrade branches keyed off machine now match
  `rg35xxh_*.bin`, giving a free OTA channel once the user's server
  offers it; the baby firmware path is NOT taken (machine is not
  `baby`/`fab4`).
- Full machine rename (not just the query) was chosen over a
  query-only hack after auditing all 12 `getMachine()` consumers:
  power-menu, ImageViewer, Experiments, and locale-suffix branches are
  all benign under the new name.
- Lesson recorded: `log:*` from `*Meta.lua` is silent during boot
  (zero meta-sourced lines in a 6700-line boot log); verify meta
  effects via behavior (query log, HELO, Udap), not boot logging.
