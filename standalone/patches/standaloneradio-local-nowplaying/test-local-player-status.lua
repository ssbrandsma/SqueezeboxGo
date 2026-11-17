-- Unit test for LocalPlayerStatus.buildStatus (pure function, no Jive).
-- Run: lua5.1 test-local-player-status.lua
package.path = "/tmp/applet-src/?.lua;/tmp/applet-src/?/init.lua;"
	.. "standalone/patches/standaloneradio-local-nowplaying/?.lua;"
	.. package.path

-- Stub the applet require path used by LocalPlayerStatus.
package.preload["applets.StandaloneRadio.StreamMetadata"] = function()
	local chunk = assert(loadfile("/tmp/applet-src/applets/StandaloneRadio/StreamMetadata.lua"))
	return chunk("applets.StandaloneRadio.StreamMetadata")
end

local LPS = require("LocalPlayerStatus")

local failures = 0
local function check(name, cond, extra)
	if cond then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (extra and (" -- " .. tostring(extra)) or ""))
	end
end

-- 1. Radio play: track/artist/album split, all strings, playlist of 1.
local s = LPS.buildStatus({
	mode = "play", waiting = false,
	stationText = "NPO Radio 1",
	title = "Song Title", artist = "Some Artist", album = "",
	display = "Some Artist - Song Title",
	elapsed = 0, duration = nil, playlistTimestamp = 1234567890,
}, { ["mixer volume"] = 63, power = 1, player_name = "RG35XXH" })
check("mode", s.mode == "play")
check("remote", s.remote == 1)
check("current_title", s.current_title == "Some Artist - Song Title")
check("playlist_tracks", s.playlist_tracks == 1)
check("playlist_cur_index", s.playlist_cur_index == 0)
check("playlist_timestamp", s.playlist_timestamp == 1234567890)
check("item text", s.item_loop[1].text == "NPO Radio 1")
check("item track", s.item_loop[1].track == "Song Title")
check("item artist", s.item_loop[1].artist == "Some Artist")
check("item album", s.item_loop[1].album == "")
check("no artwork fetch", s.item_loop[1]["icon-id"] == nil and s.item_loop[1].icon == nil
	and (s.item_loop[1].params == nil))
check("volume preserved", s["mixer volume"] == 63)
check("power preserved", s.power == 1)
check("name preserved", s.player_name == "RG35XXH")
check("time zero hides progress", s.time == 0)

-- 2. Missing metadata falls back to station text; never nil strings.
s = LPS.buildStatus({ mode = "play", stationText = "Radio 538" }, {})
check("title fallback", s.item_loop[1].track == "Radio 538")
check("artist empty string", s.item_loop[1].artist == "")
check("display fallback", s.current_title == "Radio 538")
check("power default", s.power == 1)

-- 3. Buffering reports play + waiting (bug 15814 convention).
s = LPS.buildStatus({ mode = "play", waiting = true, stationText = "X" }, {})
check("waiting", s.waitingToPlay == true and s.mode == "play")

-- 4. Stop keeps the last track (LMS stop semantics), playlist intact.
s = LPS.buildStatus({ mode = "stop", stationText = "NPO Radio 1",
	title = "T", artist = "A", display = "A - T" }, {})
check("stop mode", s.mode == "stop" and s.waitingToPlay == false)
check("stop keeps track", s.item_loop[1].track == "T")
check("stop keeps playlist", s.playlist_tracks == 1)

-- 5. Repeat/shuffle default to off (NP window concatenates them).
s = LPS.buildStatus({ mode = "play", stationText = "X" }, {})
check("repeat default", s["playlist repeat"] == "0")
check("shuffle default", s["playlist shuffle"] == "0")
s = LPS.buildStatus({ mode = "play", stationText = "X" },
	{ ["playlist repeat"] = "1", ["playlist shuffle"] = "2" })
check("repeat preserved", s["playlist repeat"] == "1")
check("shuffle preserved", s["playlist shuffle"] == "2")

-- 6. Episodes carry real position/duration, still no seek flag.
s = LPS.buildStatus({ mode = "play", stationText = "Pod",
	title = "Ep1", elapsed = 12.5, duration = 300 }, {})
check("episode time", s.time == 12.5)
check("episode duration", s.duration == 300)
check("no can_seek", s.can_seek == nil)

if failures > 0 then
	print("FAILURES: " .. failures)
	os.exit(1)
end
print("ALL PASS")
