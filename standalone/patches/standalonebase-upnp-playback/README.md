# StandaloneBase: UPnP MP3 direct-play fixes (device-proven patch)

Date: 2026-11-17. Applies to the StandaloneBase applet's
`NetworkMusic.lua` as installed via the applet installer (md5 of the
patched base: `3714ef2d3ee724248bcd571632d10b24`).
Status: hotfix live on the RG35XX H (UPnP MP3 plays end-to-end with
Now Playing); durable fix belongs in the SBStandaloneBase repo.

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
the Radio patch — `LocalPlayerStatus.lua`, included here; v3 with
the `rate` default, see below) and release it on `stopDirect`.

Two UPnP-specific additions (in the diff):

- Heartbeat re-push every 15 s while direct owns playback. The
  laptop LMS owns the player via cometd and its status arrivals wipe
  synthesized state; the heartbeat heals any wipe within seconds.
  Long-term the loopback server should own the player during
  direct play instead (Base architecture decision).
- One-time `upnp synthesis live` warn on first push (proves the
  module loaded) + `upnp synthesis unavailable` if the require
  fails. Synthesis is otherwise silent by design.

## Bug 3 (latent, same file): NP claim drops 201

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
`rate stop`); the copy here is identical.

## Repo integration notes

- `LocalPlayerStatus.lua`: vendor one copy per applet
  (`applets/StandaloneBase/`) or share one via a neutral path; it
  requires `applets.StandaloneRadio.StreamMetadata` only for ICY
  splitting — UPnP passes structured title/artist/album via
  `updateTimedMetadata`, so that dependency is load-only here.
- UPnP passes `station={name=item.title}` (no episode semantics);
  elapsed stays 0:00 (no position feed yet — progress-bar follow-up).
- The `directMode()` detector (`not has jive.slim.SlimProto module`)
  is TRUE on SqueezeboxGo although SlimProto-to-LMS works; the
  direct path is therefore always taken here. Deliberate per the
  code comment; flagging in case server-driven `queue()` was
  intended instead.
- Non-MP3 items (e.g. the FLAC folders) correctly report
  `playable=false` with no URI; their rows intentionally do nothing.
