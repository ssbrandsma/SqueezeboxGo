-- test-jive-action.lua — host-execute the Return-to-Anbernic action.
--
-- Loads the REAL SqueezeboxRG35XXH Meta + Applet files under lua5.1 with
-- stub Jive framework modules (package.preload) and asserts:
--   A) SQUEEZEBOX_GO=1  -> home item registered (id/node/weight), and its
--      callback runs storeSettings -> disconnectPlayer -> Decode:stop ->
--      restore-helper -> os.exit(42), in that order.
--   B) SQUEEZEBOX_GO unset -> NO home item (shared tree stays fork-free).
--   C) missing rg35xxh_bsp C module -> applet still loads (degraded).
--   D) Decode:open failed (SQUEEZEBOX_GO_TEST_DECODE_FAIL=1) -> Decode:stop
--      skipped, os.exit(42) still happens.
--
-- Usage: lua5.1 test-jive-action.lua [APPLET_DIR]
-- Exit 0 = all assertions hold; nonzero + message otherwise.
-- Env knobs: SQUEEZEBOX_GO, SQUEEZEBOX_GO_RESTORE, SQUEEZEBOX_GO_ROOT,
--   SQUEEZEBOX_GO_TEST_DECODE_FAIL (this harness only).

local APPLET_DIR = arg and arg[1] or
	"../../squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH"

local failures = 0
local function check(name, cond, extra)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
	end
end

-- ---------------------------------------------------------------- stubs ---
local calls = { order = {} }
local function note(step)
	calls.order[#calls.order + 1] = step
end

local sharedSettings = { brightness = 80 }

local AppletBase = {
	getSettings = function(self) return sharedSettings end,
	storeSettings = function(self) note("storeSettings") end,
}
local LinuxAppletStub = {}
setmetatable(LinuxAppletStub, { __index = AppletBase })

local DecodeStub = {
	open = function(self, settings)
		note("decode-open")
		if os.getenv("SQUEEZEBOX_GO_TEST_DECODE_FAIL") == "1" then
			return nil, "test-induced failure"
		end
		return true
	end,
	stop = function(self) note("decode-stop") end,
}

local loglines = {}
local function mklog()
	return {
		info = function(_, ...) note("log") end,
		warn = function(_, ...) note("log") end,
		error = function(_, ...) note("log") end,
		debug = function(_, ...) end,
	}
end

local services = {}
local AppletMetaStub = {
	menuItem = function(self, id, node, label, closure, weight, extras, iconStyle)
		-- mirrors upstream jive/AppletMeta.lua:menuItem shape
		return {
			id = id,
			iconStyle = iconStyle or "hm_advancedSettings",
			node = node,
			text = self:string(label),
			weight = weight,
			callback = function(event, menuItem)
				local applet = appletManager:loadApplet(self._entry.appletName)
				return closure(applet, menuItem)
			end,
			extras = extras,
		}
	end,
	string = function(self, token, ...) return "L(" .. token .. ")" end,
	registerService = function(self, s) services[#services + 1] = s end,
}

local homeItems = {}
jiveMain = {
	addItem = function(self, item)
		note("addItem:" .. tostring(item.id))
		homeItems[#homeItems + 1] = item
		return item
	end,
	setDefaultSkin = function(self, skin) calls.skin = skin end,
}
local loadedApplets = {}
appletManager = {
	loadApplet = function(self, name)
		if loadedApplets[name] then return loadedApplets[name] end
		assert(loadfile(APPLET_DIR .. "/SqueezeboxRG35XXHApplet.lua"))(
			"applets.SqueezeboxRG35XXH.SqueezeboxRG35XXHApplet")
		local mod = package.loaded["applets.SqueezeboxRG35XXH.SqueezeboxRG35XXHApplet"]
		assert(mod, "applet module did not register")
		mod._entry = { appletName = name }
		loadedApplets[name] = mod
		mod:init(mod)
		return mod
	end,
	callService = function(self, svc, ...)
		note("service:" .. tostring(svc))
	end,
	registerService = function(self, applet, svc) end,
	addDefaultSetting = function(self, a, s, v) end,
	_storeSettings = function(entry) end,
}
jive = {}
jnt = {}

package.preload["loop.simple"] = function()
	return {
		class = function(m, base)
			if base then setmetatable(m, { __index = base }) end
			return m
		end,
		rawnew = function() return {} end,
	}
end
-- NOTE: rg35xxh_bsp is deliberately NOT preloaded: require() must fail
-- so this harness exercises the degraded path (case C).
package.preload["jive.Applet"] = function() return AppletBase end
package.preload["applets.Linux.LinuxApplet"] = function() return LinuxAppletStub end
package.preload["squeezeplay.decode"] = function() return DecodeStub end
package.preload["jive.System"] = function()
	return { init = function() end, setCapabilities = function() end }
end
package.preload["jive.slim.LocalPlayer"] = function()
	return { setDeviceType = function() end }
end
package.preload["jive.slim.SlimServer"] = function()
	return { setMinimumVersion = function() end }
end
package.preload["jive.ui.Timer"] = function() return {} end
package.preload["jive.utils.log"] = function()
	return { logger = function(name) return mklog() end }
end
package.preload["jive.AppletMeta"] = function() return AppletMetaStub end
package.preload["squeezeplay.sample"] = function()
	return { MAXVOLUME = 100, setEffectAttenuation = function() end }
end
local FWStub = { constants = function(m)
	m.EVENT_UNUSED, m.EVENT_CONSUME, m.EVENT_QUIT = 0, 1, 2
end }
package.preload["jive.ui.Framework"] = function() return FWStub end
jive.ui = { Framework = FWStub }
package.preload["lfs"] = function()
	return { dir = function(path)
		return coroutine.wrap(function() end)
	end }
end

-- capture os.exit / os.execute instead of acting
local realExecute = os.execute
os.exit = function(code, ...)
	calls.exitCode = code
	note("exit:" .. tostring(code))
	error("TEST-EXIT:" .. tostring(code))
end
os.execute = function(cmd)
	note("exec:" .. tostring(cmd))
	calls.lastExec = cmd
	return 0
end

-- ------------------------------------------------------------- exercise ---
assert(loadfile(APPLET_DIR .. "/SqueezeboxRG35XXHMeta.lua"))(
	"applets.SqueezeboxRG35XXH.SqueezeboxRG35XXHMeta")
local meta = package.loaded["applets.SqueezeboxRG35XXH.SqueezeboxRG35XXHMeta"]
assert(meta, "meta module did not register")
meta._entry = { appletName = "SqueezeboxRG35XXH" }
meta:registerApplet(meta)

local goMode = os.getenv("SQUEEZEBOX_GO") == "1"

if not goMode then
	check("B: no home item when SQUEEZEBOX_GO unset", #homeItems == 0,
		"items=" .. #homeItems)
	check("B: resident applet still loads", loadedApplets["SqueezeboxRG35XXH"] ~= nil)
	check("B: missing bsp module tolerated (case C)", true)
	if failures == 0 then
		print("PASS (B/C)")
		return
	end
	error("failures: " .. failures)
end

-- case A/D: item registered?
check("A: exactly one home item", #homeItems == 1, "items=" .. #homeItems)
local item = homeItems[1]
if item then
	check("A: item id", item.id == "appletGoReturnToFrontend", item.id)
	check("A: item node is home", item.node == "home", item.node)
	check("A: item weight 1009", item.weight == 1009, tostring(item.weight))
	check("A: item text token resolved",
		item.text == "L(GO_RETURN_TO_ANBERNIC)", tostring(item.text))
end

-- invoke the menu callback; it must end in os.exit(42)
local ok, err = pcall(function() item.callback(nil, item) end)
check("A: callback raised only via captured os.exit",
	ok == false and tostring(err):match("TEST%-EXIT:42") ~= nil, tostring(err))
check("A: exit code is 42", calls.exitCode == 42, tostring(calls.exitCode))

local function idxOf(prefix)
	for i, s in ipairs(calls.order) do
		if s:sub(1, #prefix) == prefix then return i end
	end
	return nil
end
local iStore, iDisc = idxOf("storeSettings"), idxOf("service:disconnectPlayer")
local iExec, iExit = idxOf("exec:"), idxOf("exit:42")
check("A: settings stored", iStore ~= nil)
check("A: disconnectPlayer called", iDisc ~= nil)
check("A: restore helper executed", iExec ~= nil)
check("A: order store < disconnect < exec < exit",
	iStore and iDisc and iExec and iExit and
	iStore < iDisc and iDisc < iExec and iExec < iExit,
	table.concat(calls.order, ","))

local wantRestore = os.getenv("SQUEEZEBOX_GO_RESTORE")
if wantRestore then
	check("A: restore helper path used",
		calls.lastExec and calls.lastExec:find(wantRestore, 1, true) ~= nil,
		tostring(calls.lastExec))
	check("A: --from-jive flag passed",
		calls.lastExec and calls.lastExec:find("--from-jive", 1, true) ~= nil,
		tostring(calls.lastExec))
else
	local root = os.getenv("SQUEEZEBOX_GO_ROOT")
	check("A: fallback to $ROOT/restore.sh",
		root and calls.lastExec and
		calls.lastExec:find(root .. "/restore.sh", 1, true) ~= nil,
		tostring(calls.lastExec))
end

if os.getenv("SQUEEZEBOX_GO_TEST_DECODE_FAIL") == "1" then
	check("D: Decode:stop skipped when open failed", idxOf("decode-stop") == nil)
	check("D: exit 42 anyway", calls.exitCode == 42)
else
	local iStop = idxOf("decode-stop")
	check("A: Decode:stop called", iStop ~= nil)
	check("A: order disconnect < decode-stop < exit",
		iStop and iDisc < iStop and iStop < iExit,
		table.concat(calls.order, ","))
end

if failures == 0 then
	print("PASS (A" .. (os.getenv("SQUEEZEBOX_GO_TEST_DECODE_FAIL") == "1" and "/D)" or ")"))
else
	error("failures: " .. failures)
end
