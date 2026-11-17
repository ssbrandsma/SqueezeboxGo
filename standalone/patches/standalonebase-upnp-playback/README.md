# StandaloneBase: UPnP direct-play fixes (device-proven patch)

Date: 2026-11-17/18. Applies to the StandaloneBase applet's
`NetworkMusic.lua` as installed via the applet installer (pristine md5
`3714ef2d3ee724248bcd571632d10b24`).
Status: hotfix live on the RG35XX H (UPnP MP3 fully working);
durable fix belongs in the SBStandaloneBase repo.

## Bug 1 (no audio): bare-LF HTTP request — THE fix

`playDirect` hand-builds the stream request with `\n` line endings.
Synology lighttpd never answers a bare-LF request (proven by replay:
identical CRLF request → instant `200 OK` + MP3 bytes; bare-LF →
zero bytes, hangs forever). The decoder connected and sat in
silence; the log shows `connect ...` and then nothing.

Fix (one line — see `NetworkMusic.hotfix.diff` hunk 1): use `\r\n`.

## Bug 2 (NP shows Nothing): no native player state

Direct mode bypasses every server, so the Player playlist stays 0 and
stock `goNowPlaying` falls through to the empty playlist browser.
Fix: synthesize an LMS-style playerstatus on play (same module as
the Radio patch — `LocalPlayerStatus.lua`, included here) and
release it on `stopDirect`, plus:

- Heartbeat re-push every 15 s while direct owns playback. A
  SlimProto-attached LMS (here: the laptop server via cometd) wipes
  synthesized state with its own status arrivals; the heartbeat
  heals any wipe within seconds. Long-term the loopback server
  should own the player during direct play instead (Base
  architecture decision).
- One-time `upnp synthesis live` warn on first push (proves the
  module loaded) + `upnp synthesis unavailable` if the require
  fails. Synthesis is otherwise silent by design.

## Bug 3 (latent): NP claim drops 201

`npPost` treats the `201 Created` claim response as `err`, so no
session/heartbeat ever establishes (`claim done err=HTTP/1.1 201
Created success=nil`). Not fixed in this hotfix (device NP does not
need it); mirror the Radio client's `t_setResponseBody` override
for 201 in the repo. See
`../standaloneradio-local-nowplaying/README.md`.

## Bug 4 (fixed in shared module): nil `rate` aborts NP open

`getTrackElapsed` multiplies `self.rate` (`Player.lua:700`); a
synthesized status without `rate` crashes `showNowPlaying`
live-verified stack: `_updateProgress` ← `showNowPlaying`).
`LocalPlayerStatus.buildStatus` now defaults `rate` to 1 on play,
0 otherwise. Covered by the Radio patch unit test (`rate play`,
`rate stop`); the copy here is identical. Side benefit: elapsed
ticks in real time while playing (rate × correction).

## Feature 1: cover art (verified live)

`LocalPlayerStatus` accepts `artwork` (timed event `artwork_url` /
new `updateTrackArtwork`) into `item_loop[1].icon`. Stock `_getIcon`
→ `server:fetchArtwork` GETs absolute http URLs directly
(`processArtworkQueue`: `^http` → own SocketHttp; private-LAN URLs
need no proxy and `Artwork.route` passes local hosts through
unchanged). Verified: Greatest Songs cover renders in NP.

## Feature 2: pause (verified live, key + button)

- Start key: the stock C keymap (`jive_framework.c`) has NO SPACE
  entry, so the old Start→SPACE mapping was dropped on the floor.
  Remapped Start→`KEY_PLAYPAUSE` (164) in `ui/input/*.map`, which
  arrives as `JIVE_KEY_PLAY` (8, observed live).
- `NetworkMusic` matches PLAY/PAUSE codes in a global key listener
  (nothing turns them into actions) and toggles
  `decode:pauseAudio(0)` / `decode:resumeAudio()` (Radio pattern)
  + pushes PAUSED/PLAYING state. NP play button (pushes the
  `pause` action) is caught by twin action listeners.
- Proven: `upnp paused (key)` / `upnp resumed (key)` markers; NP
  icon flips ▶/❚❚; elapsed freezes. Audible silence needs an
  ears-check (hw_ptr advances on fork silence either way).
- Known cosmetic: elapsed resets to 0:00 on pause (no position
  tracking yet) instead of freezing mid-track.

## Feature 3: local queue (verified live)

Direct mode hides the server-side ADD/PLAY_NEXT entries, so a local
queue was added: track-window `Add to queue` button (visible
`Queued: <title>` confirm rows), auto-advance on natural track end
(`_directTick` idle → `playNext`, same call the skip path uses),
L1/R1 (`KEY_PREVIOUSSONG`/`KEY_NEXTSONG` → JIVE REW/FWD) for
restart-previous/next, on-screen rew/fwd buttons via
`jump_rew`/`jump_fwd` action listeners. Verified: queued
Butterflies, skipped from Hysteria → new stream + NP switched
(track, art, 1/1). Natural-end advance shares the code path but
was not soak-proven (needs a full track play-through).

## Fix 4: stale generation/token retry (code-complete, unproven live)

After daemon restarts the applet's cached UPnP generation (and
ocassionally token) goes stale → 409/403 → browse/play shows
UNAVAILABLE until the 15 s refresh or a menu re-entry heals it.
`self:request` now detects 403/409 once per call, re-discovers
servers (`requestFresh`), and retries with the fresh generation.
Could not be triggered safely live (requires killing peer-owned
daemons); needs field proof. Note: daemons also exit cleanly with
every Jive restart and only come back via applet boot-init — the
retry covers the applet side of that window.

## Repo integration notes

- `LocalPlayerStatus.lua`: vendor one copy per applet
  (`applets/StandaloneBase/`) or share one via a neutral path; it
  requires `applets.StandaloneRadio.StreamMetadata` only for ICY
  splitting — UPnP passes structured title/artist/album via
  `updateTimedMetadata`, so that dependency is load-only here.
- `playDirect(server,item,menu,keepQueue)` gained a 4th arg;
  `self.upnpQueue` (NOT `self.queue` — that name is the server-side
  op method!) holds `{server,item}` entries.
- `directMode()` (`not has jive.slim.SlimProto module`) is TRUE on
  SqueezeboxGo although SlimProto-to-LMS works; the direct path is
  therefore always taken here. Deliberate per the code comment.
- Non-MP3 items (e.g. the FLAC folders) correctly report
  `playable=false` with no URI; their rows intentionally do nothing.
- Radio Start-pause has the same gap (action listeners only, no key
  listener); same 20-line pattern applies if wanted.
- SqueezeboxGo-side changes in this repo (shipped via payload):
  `ui/input/*.map` media keys, skins NP transport (generator rule
  + toolbar icons), input + mapping gate updates.
