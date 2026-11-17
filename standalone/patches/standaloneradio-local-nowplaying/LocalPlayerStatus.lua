-- LocalPlayerStatus: synthesize LMS-style playerstatus for the native Jive
-- Player while Standalone Base (the loopback LMS) is absent.
--
-- The stock Now Playing window, home-menu item, X shortcut and screensaver
-- all render from the Player's server-driven state (playlist size, state
-- table, track-change notifications). StandaloneRadio drives the local
-- decoder directly and publishes now-playing to Base over HTTP; when Base
-- is not installed that publish fails and nothing ever populates the
-- native Player, so "Now Playing" silently does nothing (empty playlist
-- falls through to the playlist browser).
--
-- This module mirrors the small status-table contract consumed by
-- jive.slim.Player:_process_status and the NowPlaying applet, pushing a
-- one-track remote-radio status (station + ICY/timed title) on the same
-- callbacks that feed the Base publisher. It yields automatically: every
-- push is skipped once the Base client holds a session, so real server
-- state takes over the moment Base is installed with no configuration.
--
-- V1 scope: text + transport state only. Artwork fields are deliberately
-- omitted (the stock window falls back to its placeholder without any
-- server fetch). Episode seeking stays disabled (can_seek unset) because
-- seeks address the SlimProto server, not the local decoder.
--
-- SPDX-License-Identifier: GPL-2.0-or-later

local ipairs, pairs, pcall, setmetatable, tonumber, tostring, type =
	ipairs, pairs, pcall, setmetatable, tonumber, tostring, type
local os = require("os")
local string = require("string")

local StreamMetadata = require("applets.StandaloneRadio.StreamMetadata")

module(...)

local Client = {}
Client.__index = Client

-- StreamPlayer states -> Jive player mode. Buffering-family states report
-- "play" with waitingToPlay, mirroring LMS radio behaviour (bug 15814:
-- audio has not started streaming yet but mode is play).
local MODE_MAP = {
	PLAYING = "play",
	PAUSED = "pause",
	STOPPED = "stop",
	FAILED = "stop",
	RESOLVING = "play",
	CONNECTING = "play",
	RECONNECTING = "play",
	CONNECTION_LOST = "play",
}

local WAITING_STATES = {
	RESOLVING = true,
	CONNECTING = true,
	RECONNECTING = true,
	CONNECTION_LOST = true,
}

-- Fields copied from the live player state so synthesis never clobbers
-- server- or user-owned values (volume, power, alarms, sleep, ...).
local PRESERVE_KEYS = {
	"player_name", "mixer volume", "power",
	"digital_volume_control", "use_volume_control",
	"player_connected", "player_needs_upgrade", "player_is_upgrading",
	"sleep", "playlist repeat", "playlist shuffle",
	"alarm_state", "alarm_next", "alarm_version", "alarm_next2",
	"alarm_repeat", "alarm_days", "alarm_snooze_seconds",
	"alarm_timeout_seconds",
}

local function trim(value)
	return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function str(value)
	if type(value) ~= "string" then return "" end
	return value
end

local function stationName(station)
	return trim(station and (station.name or station.id or "")) or ""
end

function new(options)
	options = options or {}
	return setmetatable({
		log = options.log,
		appletManager = options.appletManager,
		baseClient = options.baseClient,
		isPlaybackOwner = options.isPlaybackOwner,
		onFirstPush = options.onFirstPush,
		station = nil,
		stationGeneration = 0,
		metadata = nil,
		timed = nil,
		mode = "stop",
		waiting = false,
		position = nil,
		duration = nil,
		pushedGeneration = nil,
		playlistTimestamp = nil,
	}, Client)
end

function Client:_log(level, ...)
	if self.log and self.log[level] then
		self.log[level](self.log, "StandaloneRadio LocalPlayerStatus: ", ...)
	end
end

function Client:_player()
	if not self.appletManager then return nil end
	local ok, player = pcall(function()
		return self.appletManager:callService("getCurrentPlayer")
	end)
	if not ok then return nil end
	return player
end

-- Yield to real server state the moment Base holds a session.
function Client:_baseHasSession()
	if not self.baseClient then return false end
	local ok, status = pcall(function() return self.baseClient:status() end)
	if not ok or type(status) ~= "table" then return false end
	return status.hasSession == true
end

function Client:_active()
	if not self.station then return false end
	if self.isPlaybackOwner and not self.isPlaybackOwner() then return false end
	if self:_baseHasSession() then return false end
	return true
end

-- Pure status-table builder (unit-testable): view carries the radio state,
-- preserve carries the live player.state fields synthesis must not clobber.
function buildStatus(view, preserve)
	view = view or {}
	preserve = preserve or {}
	local status = {}
	for _, key in ipairs(PRESERVE_KEYS) do
		if preserve[key] ~= nil then status[key] = preserve[key] end
	end
	-- The Now Playing window concatenates these ('mode' .. mode); a nil
	-- aborts the whole window open. LMS defaults: repeat/shuffle off.
	if status["playlist repeat"] == nil then status["playlist repeat"] = "0" end
	if status["playlist shuffle"] == nil then status["playlist shuffle"] = "0" end
	local stationText = str(view.stationText)
	local title = str(view.title)
	local artist = str(view.artist)
	local album = str(view.album)
	if title == "" then title = stationText end
	local display = str(view.display)
	if display == "" then display = title ~= "" and title or stationText end
	status["mode"] = view.mode or "stop"
	-- getTrackElapsed multiplies self.rate (Player.lua:700); a nil rate
	-- aborts the whole NP open. LMS rate: 1 = normal play, else 0.
	status["rate"] = (view.mode == "play") and 1 or 0
	status["waitingToPlay"] = view.waiting == true
	status["remote"] = 1
	status["current_title"] = display
	status["time"] = view.elapsed or 0
	status["duration"] = view.duration
	status["playlist_tracks"] = 1
	status["playlist_cur_index"] = 0
	status["playlist_timestamp"] = view.playlistTimestamp or os.time()
	status["power"] = preserve["power"] ~= nil and preserve["power"] or 1
	local item = {
		text = stationText,
		track = title,
		artist = artist,
		album = album,
	}
	-- Stock _getIcon fetches item.icon via server:fetchArtwork; absolute
	-- http(s) URLs are GET directly (private LAN needs no proxy).
	if type(view.artwork) == "string" and view.artwork ~= "" then
		item.icon = view.artwork
	end
	status["item_loop"] = { item }
	return status
end

function Client:_view()
	local station = self.station or {}
	local title, artist = StreamMetadata.parse(self.metadata)
	if self.timed then
		title = self.timed.title or title
		artist = self.timed.artist or artist
	end
	local album = self.timed and self.timed.album or nil
	if station.episode then
		title = station.episodeTitle or station.name
		artist = station.podcast or ""
		album = station.podcast or ""
	end
	local display = trim(self.metadata)
	if display == "" then display = stationName(station) end
	local elapsed, duration
	if station.episode then
		if type(self.position) == "number" and self.position >= 0 then
			elapsed = self.position / 1000
		end
		if type(self.duration) == "number" and self.duration > 0 then
			duration = self.duration / 1000
		elseif type(station.duration_ms) == "number" and station.duration_ms > 0 then
			duration = station.duration_ms / 1000
		end
	else
		elapsed = 0
	end
	return {
		mode = self.mode,
		waiting = self.waiting,
		artwork = self.artwork,
		stationText = stationName(station),
		title = title,
		artist = artist,
		album = album,
		display = display,
		elapsed = elapsed,
		duration = duration,
		playlistTimestamp = self.playlistTimestamp,
	}
end

function Client:_push()
	if not self:_active() then return false end
	local player = self:_player()
	if not player then
		self:_log("debug", "no current player; synthesis deferred")
		return false
	end
	local process = player._process_status
	if type(process) ~= "function" then
		self:_log("warn", "Player has no _process_status; synthesis unavailable")
		return false
	end
	local view = self:_view()
	local preserve = (type(player.state) == "table") and player.state or {}
	local status = buildStatus(view, preserve)
	local ok, err = pcall(process, player, { data = status })
	if not ok then
		self:_log("warn", "synthesis push failed: ", tostring(err))
		return false
	end
	if self.pushedGeneration ~= self.stationGeneration then
		self.pushedGeneration = self.stationGeneration
		if self.onFirstPush then
			local okCb, errCb = pcall(self.onFirstPush, self.stationGeneration)
			if not okCb then
				self:_log("warn", "onFirstPush failed: ", tostring(errCb))
			end
		end
	end
	return true
end

function Client:_noteGeneration(generation)
	generation = tonumber(generation) or self.stationGeneration
	return generation == self.stationGeneration
end

function Client:activate(station, stationGeneration)
	if not station then return end
	stationGeneration = tonumber(stationGeneration) or (self.stationGeneration + 1)
	if stationGeneration < self.stationGeneration then return end
	self.station = station
	self.stationGeneration = stationGeneration
	self.metadata = nil
	self.timed = nil
	self.artwork = nil
	self.position = nil
	self.duration = nil
	self.mode = "play"
	self.waiting = true
	self.playlistTimestamp = os.time()
	self:_push()
end

function Client:updateStation(station, stationGeneration)
	if not station then return end
	if not self:_noteGeneration(stationGeneration) then return end
	self.station = station
	self:_push()
end

function Client:updateState(state, station, stationGeneration)
	if not self:_noteGeneration(stationGeneration) then return end
	local mapped = MODE_MAP[state]
	if not mapped then return end
	if station then self.station = station end
	self.mode = mapped
	self.waiting = WAITING_STATES[state] == true
	self:_push()
end

function Client:updateMetadata(streamTitle, station, stationGeneration)
	if not self:_noteGeneration(stationGeneration) then return end
	local value = trim(streamTitle)
	if value == "" then value = nil end
	if value == self.metadata then return end
	if station then self.station = station end
	self.metadata = value
	self.timed = nil
	self:_push()
end

function Client:updateTimedMetadata(event, station, stationGeneration)
	if not self:_noteGeneration(stationGeneration) then return end
	if station then self.station = station end
	event = event or {}
	local title = type(event.title) == "string" and event.title ~= "" and event.title or nil
	local artist = type(event.artist) == "string" and event.artist ~= "" and event.artist or nil
	local album = type(event.album) == "string" and event.album ~= "" and event.album or nil
	self.timed = (title or artist or album) and { title = title, artist = artist, album = album } or nil
	local artwork = type(event.artwork_url) == "string" and event.artwork_url ~= "" and event.artwork_url or nil
	if artwork ~= self.artwork then self.artwork = artwork end
	self:_push()
end

function Client:updateTrackArtwork(url, station, stationGeneration)
	stationGeneration = tonumber(stationGeneration) or self.stationGeneration
	if stationGeneration ~= self.stationGeneration then return false end
	if station then self.station = station end
	local value = type(url) == "string" and url ~= "" and url or nil
	if value == self.artwork then return value ~= nil end
	self.artwork = value
	self:_push()
	return value ~= nil
end

function Client:updatePosition(positionMs, durationMs, stationGeneration)
	if not self:_noteGeneration(stationGeneration) then return end
	if type(positionMs) == "number" and positionMs >= 0 then
		self.position = positionMs
	end
	if type(durationMs) == "number" and durationMs > 0 then
		self.duration = durationMs
	end
	self:_push()
end

function Client:release()
	if self.mode == "stop" and self.pushedGeneration == self.stationGeneration then
		self.station = nil
		return
	end
	self.mode = "stop"
	self.waiting = false
	self:_push()
	self.station = nil
end
