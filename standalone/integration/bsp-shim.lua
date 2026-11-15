-- bsp-shim.lua — isolate Baby/Fab4 device deps behind one neutral module.
--
-- REAL grounding: the 9.0.2 device applets require device-specific C/Lua
-- modules that cannot exist on RG35XX H:
--   squeezeplay_baby/.../SqueezeboxBabyApplet.lua:5,13
--       local bsp      = require("baby_bsp")
--       local squeezeos = require("squeezeos_bsp")
--   squeezeplay_fab4/.../SqueezeboxFab4Applet.lua:5,13
--       local fab4_bsp = require("fab4_bsp")
--       local squeezeos = require("squeezeos_bsp")
-- Both also require("squeezeplay.decode") for the audio path, and Fab4
-- requires applets.Squeezebox.SqueezeboxApplet.
--
-- Contract: portable code requires ONLY this shim (plus stock jive.*).
-- Each shim function maps to the rg35xxh_bsp platform HAL
-- (docs/interface-contracts.md "Platform HAL"). Functions whose HAL call
-- does not exist yet raise UNIMPLEMENTED naming the HAL slot they will
-- satisfy — no invented behaviour.
--
-- Load path on target: share/jive/rg35xxh/bsp-shim.lua (Agent 2 Jive
-- tree); this file is the standalone-owned master copy.

-- Localize globals BEFORE module() swaps the environment (same convention
-- as NowPlayingApplet.lua:1 in the 9.0.2 tree).
local error = error

local oo = require("loop.simple")

module(..., oo.class)

local HAL = "rg35xxh_bsp" -- platform HAL module name (Agent 1+2)

local function unimplemented(what, hal_slot)
	error("UNIMPLEMENTED: bsp-shim." .. what
		.. " needs " .. HAL .. "." .. hal_slot, 2)
end

-- Display (HAL: display init/resolution, backlight/brightness).
-- Replaces baby_bsp/fab4_bsp framebuffer + backlight helpers.
function setBacklight(self, level)
	unimplemented("setBacklight", "set_backlight(level)")
end

function getDisplaySize(self)
	-- 640x480 is the SELECTED panel resolution (docs/architecture.md),
	-- returned as constants until the HAL reports it.
	return 640, 480
end

-- Power (HAL: standby/wake/shutdown hooks, battery %, charging state).
-- Replaces baby_bsp/fab4_bsp power helpers.
function getBattery(self)
	unimplemented("getBattery", "battery_percent()")
end

function shutdown(self)
	unimplemented("shutdown", "shutdown()")
end

function standby(self)
	unimplemented("standby", "standby()")
end

-- Audio device select (HAL: audio device enumerate/select; default
-- internal sun4i-codec, USB DAC optional). Replaces the ALSA-device
-- knowledge inside the Baby/Fab4 applets + squeezeplay.decode wiring.
-- Playback exclusivity itself is enforced by audio-owner (Agent 3).
function getAudioDevices(self)
	unimplemented("getAudioDevices", "audio_devices()")
end

function selectAudioDevice(self, id)
	unimplemented("selectAudioDevice", "audio_select(id)")
end

-- Network events (HAL: network up/down events). Replaces the
-- squeezeos_bsp networking hooks used by SetupNetworking flows.
function isNetworkUp(self)
	unimplemented("isNetworkUp", "network_up()")
end

return _M
