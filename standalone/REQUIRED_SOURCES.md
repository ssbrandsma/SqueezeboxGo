# Standalone required sources (WP1 survey, 2026-11-15)

Survey scope: entire home dir (`/home/sjoerd`, incl. `~/projects`,
`~/squeezeos`, `~/squeeze_userbuild`, `~/squeezify-build`,
`~/radio-kernel-0228-test`, `~/jive-*-20261024`, `~/yocto-work`,
`~/buildroot`) plus the workspace. Method: `find -iname` sweeps for
`*standalone* *nowplay* *now-play* *qobuz* *spotify* *librespot* *fab4*
*tinysc* *tinylms* *squeezeplay* *squeezelite* *squeezeslave* *vpn*
*openvpn* *wireguard*`, then targeted tree inventories. Nothing was
copied into git; paths below are the fetch/vendoring inputs for WP1+.

Reference version: SqueezeOS `9.0.2` (`squeezeplay.version` in each
local tree; `SQUEEZEOS_DISTRO_RELEASE = "9.0.2"` in
`~/squeezeos/poky/meta-squeezeos/conf/distro/squeezeos.conf`).

## FOUND (real, on disk)

| # | Component | Path(s) | Notes |
|---|---|---|---|
| 1 | NowPlaying applet (Lua) | `~/squeeze_userbuild/source/src/squeezeplay/share/applets/NowPlaying/` (identical md5 `08a4bf2d00953c57189d5cf609c05f68` in `~/jive-performance-source-20261024`, `~/jive-partial-rotation-offline-20261024`, `~/jive-render-diag-20261024`) | 1959-line `NowPlayingApplet.lua` + `NowPlayingMeta.lua`; resident applet, services `goNowPlaying`/`hideNowPlaying`; consumes `jive.slim.Player` notifications |
| 2 | Player/Artwork APIs (Lua) | `.../squeezeplay/share/jive/slim/{Player,LocalPlayer,SlimServer,ArtworkCache}.lua` (same 4 trees) | `getPlayerStatus()` returns `Player.state` (`item_loop`, `mode`); `server:fetchArtwork(iconId, icon, size)`; artwork cache is REAL |
| 3 | Baby (Radio) device applets | `~/squeeze_userbuild/source/src/squeezeplay_baby/share/applets/` (+ same 3 jive copies): `SqueezeboxBaby`, `LineIn`, `SetupWallpaper`, `SetupWelcome`, `SqueezeboxBaby`, test applets | Deps to isolate: `baby_bsp`, `squeezeos_bsp`, `squeezeplay.decode` (see `SqueezeboxBabyApplet.lua:5-16`) |
| 4 | Fab4 (Touch) device applets | `~/squeeze_userbuild/source/src/squeezeplay_fab4/share/applets/` (+ copies): `SqueezeboxFab4`, `MediaManager`, `SetupStorage`, `WirelessBridging`, `AutoSkin`, tests | Deps to isolate: `fab4_bsp`, `squeezeos_bsp`, `squeezeplay.decode`, `applets.Squeezebox.SqueezeboxApplet` |
| 5 | SqueezeOS platform applets | `~/squeeze_userbuild/source/src/squeezeplay_squeezeos/share/applets/` (+ copies): `SetupNetworking`, `SetupSSH`, `SetupFirmwareUpgrade`, `SetupFactoryReset`, `Diagnostics`, `CrashLog`, `Squeezebox`, `TestDisplay` | `SetupNetworking` covers wifi; no VPN applet here |
| 6 | SqueezeOS build recipes | `~/squeezeos/poky/meta-squeezeos/packages/` | `squeezelite_2.0.0.bb`, `openvpn_2.5.11.bb` (SRC `https://swupdate.openvpn.org/community/releases/`), `libspotify_svn.bb` (**private** `SQUEEZEOS_PRIVATE_SVN`, unusable), `squeezecenter_svn.bb`, `squeezeplay{,-baby,-fab4,-jive,-squeezeos,-private}_svn.bb` |
| 7 | SCM pins for vendoring | `~/squeezeos/poky/meta-squeezeos/conf/distro/squeezeos.conf:31-36` | `SQUEEZEPLAY_SCM=github.com/ralph-irving/squeezeos-squeezeplay.git;branch=public/9.0`, `SQUEEZECENTER_SCM=github.com/ralph-irving/slimserver.git;tag=9.0.2` (replaces dead `Logitech/slimserver`, commented out in file) |
| 8 | Device backup residue | `~/radio-kernel-0228-test/device-extra/mnt/sbdata/applets/StandaloneBase/sbubifs-authorized.ko` | Kernel module ONLY, no Lua/applet sources; name match is a false friend for source purposes |

## MISSING (no sources anywhere on disk)

| # | Component | What was searched | Required repo / component / version for integration |
|---|---|---|---|
| 9 | Spotify service backend | No Spotify/Qobuz applets in any Jive tree (only `ChooseMusicSource` shell + UI `RadioButton`/`RadioGroup` widgets); `libspotify` recipe points at private SVN; `~/squeezify-build/phase{5,7}-librespot/` holds cargo **fingerprints only**, no `.rs`/Cargo sources; `~/.cargo/git/checkouts` has only unrelated `qonductor` | `github.com/librespot-org/librespot` (Spotify Connect), version TBD — WP1 vendor step pins a tag + verifies `aarch64-linux-gnu` build. Lead approval required. Legacy `libspotify` is dead upstream: do NOT pursue. |
| 10 | Qobuz service backend | Same sweep, zero hits | Qobuz LMS plugin from `github.com/ralph-irving/slimserver.git;tag=9.0.2` (server-side) and/or a device-side Qobuz Connect client TBD in WP3. Pin after source fetch; Lead approval required. |
| 11 | Radio / Music service apps | No `Radio`/`Music` service sources; these were mysqueezebox.com/LMS apps, never in the Jive tree | Same `slimserver;tag=9.0.2` plugin set; device side reuses `SlimBrowser`/`SlimMenus` already in tree (item 2). |
| 12 | Local web management UI | Zero hits for a device-local web UI | To be defined in WP3 against the route registry in `standalone/integration/web-routes.sh`. LMS web UI inside `slimserver;tag=9.0.2` is server-side only, not a device UI. |
| 13 | HTTP proxy component | Zero hits (only kernel `nf_*_standalone.c`, unrelated) | No upstream identified yet; WP3 decision. The `proxy` slot stays UNIMPLEMENTED until a real requirement + source exists. |
| 14 | VPN client integration | `openvpn_2.5.11.bb` recipe + `openvpn.net` tarball URI found (item 6), plus `tun.ko-{jive,baby,fab4}` blobs referenced by the recipe; **no** device-side VPN applet, config, or `tun.ko` source; `~/yocto-work` openvpn/wireguard recipes are generic layers, not device integration | `openvpn_2.5.11` tarball per recipe for the daemon; kernel `tun` for H700 must come from the WP1 kernel tree (Agent 1), never from the 2.6-era `tun.ko` blobs. |

## Vendoring rule (applies to all WP1+ work)

Fetch pinned sources to `/tmp`, never into git wholesale. Commit only
small reviewable patches/notes under `squeezeplay/upstream/` (refs and
notes only, per `docs/build.md`). Baby/Fab4-only Lua/C deps
(`baby_bsp`, `fab4_bsp`, `squeezeos_bsp`, `squeezeplay.decode`) stay
behind `standalone/integration/` and are never linked directly.
