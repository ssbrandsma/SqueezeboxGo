
-- SqueezeboxRG35XXHApplet - Anbernic RG35XX H device applet (WP2 skeleton).
--
-- Fab4 pattern (SqueezeboxFab4Applet.lua): resident device applet that
--   * require()s its <machine>_bsp C module (uevent pump),
--   * System:init({machine=...}) + setCapabilities(),
--   * owns brightness/power/audio-device hooks and the Decode:open wiring.
--
-- RG35XX-H adaptations (see ../README.md):
--   * subclasses applets.Linux.LinuxApplet (present in the 758bc11 open
--     tree; SqueezeboxApplet lives in the squeezeos tree and is absent).
--   * keys arrive via SDL through Agent 4's evdev2jive map - nothing to
--     grab here; power key is handled as a jive key event (see below).
--   * sysfs nodes are PROBED, never hardcoded: exact H700 backlight /
--     power-supply / codec card names are unknown until hardware exists.
--     Every probe failure degrades to log + nil, never a crash.

local pcall, type, tonumber, tostring, pairs = pcall, type, tonumber, tostring, pairs

-- board specific driver (uevent pump; keys intentionally not grabbed).
-- Optional at runtime: the App Center payload ships Lua only (no .so
-- build yet), so a missing module degrades to "no hotplug events"
-- instead of failing the whole applet (and its Return-to-Anbernic item).
local _bspOk, rg35xxh_bsp = pcall(require, "rg35xxh_bsp")
if not _bspOk then
	rg35xxh_bsp = nil
end

local oo      = require("loop.simple")
local os      = require("os")
local io      = require("io")
local string  = require("string")
local lfs     = require("lfs")

local Applet       = require("jive.Applet")
local LinuxApplet  = require("applets.Linux.LinuxApplet")
local Decode       = require("squeezeplay.decode")
local System       = require("jive.System")

local LocalPlayer  = require("jive.slim.LocalPlayer")

local Timer        = require("jive.ui.Timer")

local log          = require("jive.utils.log").logger("applet.RG35XXH")

local jiveMain      = jiveMain
local appletManager = appletManager

local settings = nil

-- Distinctive process exit code: "user chose Return to Anbernic".
-- Contract (squeezebox-go/README.md "Exit-code contract"): launch.sh maps
-- 42 to the clean frontend-restore path. Any other exit restores too
-- (launcher trap) but is logged as unexpected. Must match the launcher's
-- SQUEEZEBOX_GO_EXIT_FRONTEND. Chosen away from 0/1/2/126/127/128+N and
-- from jive.c's own exit(-1)=255 init-failure code.
local EXIT_RETURN_TO_FRONTEND = 42


-- Hack around global scope to allow bsp C code to call back into us
-- (same convention as the Fab4 applet).
local ueventListeners = {}
local ourUeventHandler
ueventHandler = function(...)
	ourUeventHandler(...)
end


module(..., jive.ui.Framework.constants)
oo.class(_M, LinuxApplet)


-- ---------------------------------------------------------------------------
-- sysfs helpers (probe, don't hardcode: H700 node names are TBD on hardware)
-- ---------------------------------------------------------------------------

-- First directory under /sys/class/<class>, or nil. Deterministic order.
local function _firstSysfsNode(class)
	local base = "/sys/class/" .. class
	local iter, dir = pcall(lfs.dir, base)
	if not iter or not dir then
		return nil
	end
	local best = nil
	for entry in dir do
		if entry ~= "." and entry ~= ".." then
			if not best or entry < best then
				best = entry
			end
		end
	end
	if best then
		return base .. "/" .. best
	end
	return nil
end


local function _readNumber(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local n = tonumber(f:read("*l"))
	f:close()
	return n
end


local function _writeNumber(path, val)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(tostring(val))
	f:close()
	return true
end


-- ---------------------------------------------------------------------------
-- cpuinfo (overrides LinuxApplet.parseCpuInfo: upstream crashes on ARM
-- boards whose /proc/cpuinfo has a Serial line - `string.gsub/serial`
-- typo performs arithmetic on a function. This version never raises.)
-- ---------------------------------------------------------------------------

function parseCpuInfo(self)
	local f = io.open("/proc/cpuinfo", "r")
	if not f then
		return
	end
	for line in f:lines() do
		local uuid = string.match(line, "UUID%s+:%s+([%x-]+)")
		if uuid then
			self._uuid = string.gsub(uuid, "[^%x]", "")
		end
		local serial = string.match(line, "Serial%s+:%s+([%x-]+)")
		if serial then
			self._serial = string.gsub(serial, "[^%x]", "")
		end
		local rev = string.match(line, "Revision%s+:%s+(%S+)")
		if rev then
			self._revision = tonumber(rev)
		end
		local hw = string.match(line, "Hardware%s+:%s*(.+)%s*$")
		if hw then
			self._hardware = hw
		end
	end
	f:close()
end


-- ---------------------------------------------------------------------------
-- init (fab4: parseCpuInfo, System:init, capabilities, Decode:open)
-- ---------------------------------------------------------------------------

function init(self)
	settings = self:getSettings()

	-- read uuid, serial and revision (LinuxApplet helper)
	self:parseCpuInfo()

	System:init({
		machine  = "rg35xxh",
		uuid     = self._uuid,
		revision = self._revision,
	})

	System:setCapabilities({
		-- No touch panel, no IR receiver on this handheld.
		-- Keys/buttons/sticks arrive as SDL events (Agent 4 map).
		["powerKey"] = 1,
	})

	-- Local player identity (fab4 registers "fab4"/"Squeezebox Touch").
	LocalPlayer:setDeviceType("rg35xxh", "Squeezebox RG35XX H")

	-- uevent listener table (pattern -> {callbacks}); the C pump calls
	-- ourUeventHandler(action, msg) once per netlink datagram.
	ourUeventHandler = function(action, msg)
		self:_onUevent(action, msg)
	end

	-- Default listeners: USB DAC hotplug hints + power-supply change.
	self:addUeventListener("sound", function(action, msg)
		log:info("sound uevent ", action)
	end)
	self:addUeventListener("power_supply", function(action, msg)
		log:info("power_supply uevent ", action)
	end)

	self:initBrightness()
	self:initPower()

	-- Open the audio path with our Meta defaults (see Meta file).
	-- nil+err is a clean "no audio" state, not fatal (matches the
	-- decode.c null/alsa/portaudio fallback chain semantics).
	local ok, err = Decode:open(settings)
	self._decodeOpen = ok and true or false
	if not ok then
		log:warn("Decode:open failed: ", err)
	else
		log:info("Decode:open ok")
	end

	if not _bspOk then
		log:warn("rg35xxh_bsp C module absent: hotplug events disabled")
	end

	log:info("SqueezeboxRG35XXH init done")
end


-- ---------------------------------------------------------------------------
-- uevent dispatch (fab4: addUeventListener/ourUeventHandler)
-- ---------------------------------------------------------------------------

function addUeventListener(self, pattern, listener)
	local list = ueventListeners[pattern]
	if not list then
		list = {}
		ueventListeners[pattern] = list
	end
	list[#list + 1] = listener
end


function _onUevent(self, action, msg)
	if type(msg) ~= "table" then
		return
	end
	local subsystem = msg["SUBSYSTEM"]
	local list = subsystem and ueventListeners[subsystem]
	if not list then
		return
	end
	for _, listener in pairs(list) do
		local ok, err = pcall(listener, action, msg)
		if not ok then
			log:warn("uevent listener failed: ", err)
		end
	end
end


-- ---------------------------------------------------------------------------
-- brightness (contract HAL: backlight/brightness)
-- ---------------------------------------------------------------------------

function initBrightness(self)
	settings.brightness = settings.brightness or 80

	self._blPath = _firstSysfsNode("backlight")
	if not self._blPath then
		log:warn("no backlight sysfs node (headless/qml?)")
		return
	end
	self._blMax = _readNumber(self._blPath .. "/max_brightness") or 255
	log:info("backlight: ", self._blPath, " max=", self._blMax)

	self:setBrightness(settings.brightness)
end


-- level: 0..100 (UI scale, fab4 MAX_BRIGHTNESS_LEVEL convention).
function getBrightness(self)
	if not self._blPath then
		return settings and settings.brightness or 80
	end
	local raw = _readNumber(self._blPath .. "/brightness")
	if not raw then
		return settings.brightness
	end
	return math.floor(raw * 100 / self._blMax + 0.5)
end


function setBrightness(self, level)
	level = math.max(0, math.min(100, tonumber(level) or 0))
	settings.brightness = level
	if self._blPath then
		local raw = math.floor(level * self._blMax / 100 + 0.5)
		if not _writeNumber(self._blPath .. "/brightness", raw) then
			log:warn("backlight write failed")
		end
	end
end


-- ---------------------------------------------------------------------------
-- power (contract HAL: standby/wake/shutdown, battery %, charging)
-- poweroff/reboot override LinuxApplet's squeezeos.* calls, which do not
-- exist on this target (no squeezeos_bsp module).
-- ---------------------------------------------------------------------------

function initPower(self)
	self._psPath = nil
	-- Prefer a battery/capacity node, else any power_supply node.
	local base = "/sys/class/power_supply"
	local ok, dir = pcall(lfs.dir, base)
	if ok and dir then
		-- Single pass: lfs closes the DIR* at exhaustion, so the
		-- iterator cannot be rewound for a second loop.
		local first = nil
		for entry in dir do
			if entry == "battery" or entry == "BAT0" or entry == "axp20x-battery" then
				self._psPath = base .. "/" .. entry
				break
			end
			if entry ~= "." and entry ~= ".." and not first then
				first = entry
			end
		end
		if not self._psPath and first then
			self._psPath = base .. "/" .. first
		end
	end
	if self._psPath then
		log:info("power_supply: ", self._psPath)
	else
		log:warn("no power_supply sysfs node")
	end
end


-- Battery percent 0..100, or nil when unknown (contract: battery %).
function batteryPercent(self)
	if not self._psPath then
		return nil
	end
	return _readNumber(self._psPath .. "/capacity")
end


-- Charging state string ("Charging"/"Discharging"/..., or nil).
function chargingState(self)
	if not self._psPath then
		return nil
	end
	local f = io.open(self._psPath .. "/status", "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end


-- Standby: dim to black + suspend. Suspend-to-RAM on H700 needs a validated
-- wake path (power key as wakeup source); until hardware validates it this
-- is screen-blank only and logs loudly. (Contract hook: standby/wake.)
function standby(self)
	log:warn("standby: suspend-to-RAM not validated on H700; blanking only")
	self._preStandbyBrightness = self:getBrightness()
	self:setBrightness(0)
	-- TODO(hardware): echo mem > /sys/power/state after wake-path test.
end


function wake(self)
	if self._preStandbyBrightness then
		self:setBrightness(self._preStandbyBrightness)
		self._preStandbyBrightness = nil
	end
end


-- Graceful shutdown through init (overrides LinuxApplet squeezeos call).
function poweroff(self, now)
	log:info("poweroff now=", now)
	appletManager:callService("disconnectPlayer")
	os.execute("/sbin/poweroff")
end


function reboot(self)
	log:info("reboot")
	appletManager:callService("disconnectPlayer")
	os.execute("/sbin/reboot")
end


-- ---------------------------------------------------------------------------
-- audio device hooks (contract HAL: enumerate/select; internal default,
-- USB DAC optional). Playback exclusivity is enforced by audio-owner
-- (Agent 3), not here. Card-index policy comes from Agent 1 udev + Agent 3
-- asound.conf (internal pinned to 0, USB DACs 1+).
-- ---------------------------------------------------------------------------

-- Returns a list of { id, name } from /proc/asound/cards; empty when ALSA
-- is absent (headless CI). Never raises.
function audioDevices(self)
	local devs = {}
	local f = io.open("/proc/asound/cards", "r")
	if not f then
		return devs
	end
	for line in f:lines() do
		local id, name = string.match(line, "^%s*(%d+)%s+%[[^%]]+%]%s*:%s*(.+)$")
		if id then
			devs[#devs + 1] = { id = id, name = name }
		end
	end
	f:close()
	return devs
end


-- Select an output device by PCM alias ("internal"/"usb"/"default" per
-- audio/alsa/asound.conf). Skeleton: records the choice in settings and
-- exports it for the next Decode:open; live re-open is a TODO.
function selectAudioDevice(self, pcm)
	log:info("selectAudioDevice: ", pcm)
	settings.alsaPlaybackDevice = pcm
	settings.alsaCaptureDevice = pcm
	self:storeSettings()
	-- TODO: live re-open (Decode:close + Decode:open) after Agent 3
	-- confirms the single-holder handoff sequence.
end


-- ---------------------------------------------------------------------------
-- SqueezeboxGo: Return to Anbernic (home-menu action, StockOS App Center)
-- ---------------------------------------------------------------------------
--
-- Menu registration lives in the Meta file and is gated on
-- SQUEEZEBOX_GO=1, so mainline firmware never sees this item (shared
-- codebase, no fork). The sequence: save settings -> stop playback ->
-- release the decode pipeline -> restore mixer/fb via the launcher's
-- helper -> quit with EXIT_RETURN_TO_FRONTEND.
--
-- Every step is best-effort (pcall + log): even a partial cleanup must
-- still end in os.exit(42), because the launcher restores the frontend
-- on ANY exit via its trap. os.exit (rather than Framework:quit, which
-- always yields exit 0 through JiveMain) is what carries the
-- distinctive code; process teardown releases all fds/children.
function returnToFrontend(self)
	log:info("returnToFrontend: leaving Jive for the Anbernic frontend")

	-- 1. persist our settings (brightness, ALSA device choice). Jive
	-- offers no store-all API; other applets persist on their own
	-- change paths, same as a normal quit.
	local ok, err = pcall(function() self:storeSettings() end)
	if not ok then
		log:warn("returnToFrontend: storeSettings failed: ", err)
	end

	-- 2. stop playback: drop the server session (Quit-applet pattern),
	-- then halt the local decode pipeline (Playback.lua pattern).
	ok, err = pcall(function()
		appletManager:callService("disconnectPlayer")
	end)
	if not ok then
		log:warn("returnToFrontend: disconnectPlayer failed: ", err)
	end
	if self._decodeOpen then
		ok, err = pcall(function() Decode:stop() end)
		if not ok then
			log:warn("returnToFrontend: Decode:stop failed: ", err)
		end
	end

	-- 3. restore mixer + framebuffer mode through the launcher helper.
	-- Belt and braces: launch.sh runs the same restore from its trap,
	-- so a failure here is still recovered after we exit.
	local restore = os.getenv("SQUEEZEBOX_GO_RESTORE")
	if not restore then
		local root = os.getenv("SQUEEZEBOX_GO_ROOT")
		if root then
			restore = root .. "/restore.sh"
		end
	end
	if restore then
		ok, err = pcall(function()
			return os.execute(string.format("%q --from-jive", restore))
		end)
		-- err holds os.execute's status on success, the error on failure
		log:info("returnToFrontend: restore helper rc=", err)
	else
		log:warn("returnToFrontend: no restore helper in env " ..
			"(SQUEEZEBOX_GO_RESTORE/SQUEEZEBOX_GO_ROOT unset); " ..
			"launcher trap still restores")
	end

	-- 4. quit with the distinctive code the launcher maps to
	-- frontend-restore. Unconditional: we must never fall back into
	-- the event loop with half-released devices.
	log:info("returnToFrontend: exit ", EXIT_RETURN_TO_FRONTEND)
	os.exit(EXIT_RETURN_TO_FRONTEND)
end


--[[
=head1 LICENSE

Copyright 2026 Squeezebox RG35XX H contributors. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
