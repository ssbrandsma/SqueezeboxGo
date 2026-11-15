# Now Playing state schema (v1)

Single authoritative state per `docs/interface-contracts.md` ("Now
Playing" section). Field set is derived from the REAL 9.0.2 sources —
`NowPlayingApplet.lua` (1959 lines), `NowPlayingMeta.lua`, and
`jive/slim/Player.lua` in `~/squeeze_userbuild/source/src/` — not
invented. Publishers: Jive screens, web mgmt, existing publisher
interfaces. No per-source duplicates.

## Source grounding

| Schema field | Real API / notification |
|---|---|
| `track`, `artist`, `album` | `_updateTrack(trackinfo,pos,length)`: `trackTable[1..3]`; remote streams send text, local music sends `track_id` + `item_loop` |
| `station` | `notify_playerTitleStatus(player, text, duration)` — remote-stream text path |
| `artwork.icon_id`, `artwork.size` | `_getIcon`: `item["icon-id"]`/`item["icon"]` via `server:fetchArtwork(iconId, icon, ARTWORK_SIZE)`; placeholder via `params.track_id` |
| `mode` | `notify_playerModeChange`; tokens `off/play/pause/stop` (`modeTokens` table); `player:getPlayMode()` |
| `power` | `notify_playerPower`; `player:isPowerOn()` |
| `position_s`, `duration_s` | `player:getTrackElapsed()`; seek via `player:gototime()`; `player:isTrackSeekable()` |
| `volume` | `player:getVolume()` / `player:volume()`; `player:useVolumeControl()`; `notify_playerDigitalVolumeControl` |
| `repeat`, `shuffle` | `notify_playerRepeatModeChange` (`repeatOff/repeatSong/repeatPlaylist`), `notify_playerShuffleModeChange` (`shuffleOff/shuffleSong/shuffleAlbum`) |
| `playlist.index`, `playlist.size` | `player:getPlaylistCurrentIndex()`, `player:getPlaylistSize()`; `notify_playerPlaylistChange` |
| `player_id`, `is_local` | `player:getId()`; `player:isLocal()` / `player:isRemote()`; `notify_playerCurrent`, `notify_playerDelete` |
| `source_id` | Contract addition: which adapter holds audio-owner (`squeezeplay`, `spotify`, `qobuz`, `radio`, `music`, ...) |
| `format`, `rate_hz`, `depth_bits` | Contract addition: from the audio path (Agent 3); no Jive equivalent read |
| `output_device` | Contract addition: ALSA device from platform HAL enumerate/select |

## JSON encoding

Published by `standalone/base/nowplaying-pub.sh` to
`$NP_STATE_DIR/nowplaying.json` (default `/run/squeezebox/nowplaying.json`;
`NP_STATE_DIR` override for tests). Writers replace the file atomically
(write temp + rename). All fields always present; unknown values are
`null`, never omitted.

```json
{
  "schema": 1,
  "updated": "2026-11-15T21:30:00Z",
  "source_id": "squeezeplay",
  "player_id": "aa:bb:cc:dd:ee:ff",
  "is_local": true,
  "power": true,
  "mode": "play",
  "track": "Track title",
  "artist": "Artist",
  "album": "Album",
  "station": null,
  "artwork": { "icon_id": "1234", "size": "100x100" },
  "position_s": 42,
  "duration_s": 300,
  "seekable": true,
  "volume": 80,
  "repeat": "repeatOff",
  "shuffle": "shuffleOff",
  "playlist": { "index": 3, "size": 12 },
  "format": "FLAC",
  "rate_hz": 44100,
  "depth_bits": 16,
  "output_device": "hw:0,0"
}
```

`mode` enum: `off` | `play` | `pause` | `stop` (matches `modeTokens`).
`repeat` enum: `repeatOff` | `repeatSong` | `repeatPlaylist`.
`shuffle` enum: `shuffleOff` | `shuffleSong` | `shuffleAlbum`.
