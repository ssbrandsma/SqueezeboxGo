
-- SqueezeboxRG35XXHMeta - resident applet registration (fab4 pattern).

local pairs = pairs

local oo            = require("loop.simple")

local os            = require("os")

local AppletMeta    = require("jive.AppletMeta")
local LocalPlayer   = require("jive.slim.LocalPlayer")
local SlimServer    = require("jive.slim.SlimServer")

local Sample        = require("squeezeplay.sample")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		-- ALSA defaults mirror the decode_alsa.c C fallbacks (30000/3)
		-- until target soak says otherwise; device aliases come from
		-- audio/alsa/asound.conf ("default" -> internal codec).
		alsaPlaybackDevice      = "default",
		alsaPlaybackBufferTime  = 30000,
		alsaPlaybackPeriodCount = 3,
		-- No effects fork: single-holder audio (no dmix by design)
		-- means a second jive_alsa on the same PCM would fail its
		-- open. UI sounds stay silent until Agent 3 + Lead pick an
		-- effects routing (dmix exception vs playback-fifo mix).
		-- alsaEffectsDevice is deliberately absent (nil = no fork).
		alsaSampleSize = "16",
		brightness     = 80,
	}
end


function upgradeSettings(meta, settings)
	-- fill in any blanks
	local defaults = defaultSettings(meta)
	for k, v in pairs(defaults) do
		if settings[k] == nil then
			settings[k] = v
		end
	end

	return settings
end


function registerApplet(meta)
	-- Set player device type
	LocalPlayer:setDeviceType("rg35xxh", "Squeezebox RG35XX H")

	-- Set the minimum support server version
	SlimServer:setMinimumVersion("7.5")

	-- System sound effects attenuation
	Sample:setEffectAttenuation(Sample.MAXVOLUME)

	-- BSP is a resident Applet
	appletManager:loadApplet("SqueezeboxRG35XXH")

	-- SqueezeboxGo (StockOS App Center): "Return to Anbernic" home
	-- item. Shown ONLY when the launcher exports SQUEEZEBOX_GO=1, so
	-- the shared tree stays fork-free (mainline firmware never sets
	-- it). Weight 1009 sits just above the desktop Quit item (1010);
	-- the callback is SqueezeboxRG35XXHApplet:returnToFrontend.
	if os.getenv("SQUEEZEBOX_GO") == "1" then
		jiveMain:addItem(meta:menuItem('appletGoReturnToFrontend', 'home',
			"GO_RETURN_TO_ANBERNIC",
			function(applet, ...) applet:returnToFrontend(...) end,
			1009))
	end

	-- audio playback defaults
	appletManager:addDefaultSetting("Playback", "enableAudio", 1)

	jiveMain:setDefaultSkin("RG35XXHBaseSkin")

	-- services (subset of fab4's, matching implemented hooks)
	meta:registerService("getBrightness")
	meta:registerService("setBrightness")
	meta:registerService("poweroff")
	meta:registerService("reboot")
	meta:registerService("standby")
	meta:registerService("wake")
	meta:registerService("batteryPercent")
	meta:registerService("chargingState")
	meta:registerService("audioDevices")
	meta:registerService("selectAudioDevice")
	meta:registerService("wasLastShutdownUnclean")
	meta:registerService("addUeventListener")
end


--[[

=head1 LICENSE

Copyright 2026 Squeezebox RG35XX H contributors. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
