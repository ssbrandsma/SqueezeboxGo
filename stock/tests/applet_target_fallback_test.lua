-- applet_target_fallback_test.lua — behavioral test for the rg35xxh
-- applet-target fallback (stock/bundle/rg35xxh-identity.patch).
--
-- sendRequest/menuSink below mirror the patched functions verbatim
-- (only the UI tail of menuSink is replaced by `rendered = ...`);
-- test-rg35xxh-identity.sh couples mirror and patch via shared
-- marker strings, so drift fails loudly. Server callbacks are
-- queued + pumped to preserve the real async ordering.
-- Run: lua5.1 applet_target_fallback_test.lua

-- ---- stubs -------------------------------------------------------
local queries = {}   -- {server=..., target=...} per userRequest
local pending = {}   -- queued async callbacks
local rendered = "unset"

log = { info = function() end, debug = function() end }

local fakeServers = {}
appletManager = {
    callService = function(_, name)
        assert(name == "iterateSqueezeCenters")
        local i = 0
        return function()
            i = i + 1
            if fakeServers[i] then
                return i, fakeServers[i]
            end
        end
    end,
}

local function fakeServer(name, isSN, replies)
    return {
        name = name,
        isSqueezeNetwork = function() return isSN end,
        userRequest = function(_, cb, _, req)
            local target = req[2]:match("^target:(.*)$")
            queries[#queries + 1] = { server = name, target = target }
            pending[#pending + 1] = {
                cb = cb, data = replies[target] or { count = 0 },
            }
        end,
        getIpPort = function() return "127.0.0.1", 9000 end,
    }
end

local function pump()
    while #pending > 0 do
        local batch = pending
        pending = {}
        for _, p in ipairs(batch) do
            p.cb({ data = p.data }, nil)
        end
    end
end

-- ---- mirrored patched code (identity patch hunks) ----------------
local menuSink -- forward decl (both are module globals in Jive)
local function sendRequest(self, server, target)
    target = target or "rg35xxh"
    log.info("sending query to ", tostring(server), " target:", target)
    local opt = not self:getSettings()["_RECONLY"]
    server:userRequest(
        function(chunk, err)
            if err then
                log.debug(err)
            elseif chunk then
                menuSink(self, server, chunk.data)
            end
        end,
        nil,
        { "jiveapplets",
          "target:" .. target,
          "version:" .. self.version,
          opt and "optstr:other|user" or "optstr:none",
      }
    )
end

menuSink = function(self, server, data)
    if server ~= nil then
        data.count = tonumber(data.count)
        if self.best.count == nil or self.best.count < data.count then
            self.best = { server = server, count = data.count,
                           data = data }
        end
        self.waitingfor = self.waitingfor - 1
    else
        self.waitingfor = 0
    end

    if self.waitingfor ~= 0 then
        return
    end

    -- RG35XXH: no platform entries yet -> fall back to Radio (baby)
    if (self.best.count == nil or self.best.count == 0)
        and not self.triedBaby then
        log.info("no rg35xxh entries - falling back to baby target")
        self.triedBaby = true
        self.best = {}
        for _id, _server in appletManager:callService(
                "iterateSqueezeCenters") do
            if not _server:isSqueezeNetwork() then
                sendRequest(self, _server, "baby")
                self.waitingfor = self.waitingfor + 1
            end
        end
        if self.waitingfor > 0 then
            return -- timer restart: pump() continues the async flow
        end
    end

    if (self.best.count == nil or self.best.count == 0) and self.sn then
        sendRequest(self, self.sn)
        self.sn = nil
        self.waitingfor = 1
        return -- timer restart: pump() continues the async flow
    end

    rendered = self.best.data -- UI menu build elided in test
end

local function runMenu(servers)
    queries = {}
    pending = {}
    rendered = "unset"
    fakeServers = servers
    local self = { version = "9.0.0.541", waitingfor = 0, best = {},
                   triedBaby = false, sn = nil,
                   getSettings = function() return {} end }
    for _, server in appletManager:callService(
            "iterateSqueezeCenters") do
        if server:isSqueezeNetwork() then
            self.sn = server
        else
            sendRequest(self, server)
            self.waitingfor = self.waitingfor + 1
        end
    end
    pump()
    return self
end

-- ---- cases -------------------------------------------------------
local failures = 0
local function check(name, cond, extra)
    if cond then
        print("PASS " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. (extra and (" (" .. extra .. ")") or ""))
    end
end

local function targets()
    local t = {}
    for _, q in ipairs(queries) do
        t[#t + 1] = q.target
    end
    return table.concat(t, ",")
end

-- 1. empty rg35xxh -> baby fallback queried, baby entries rendered
do
    runMenu({ fakeServer("repo", false,
        { rg35xxh = { count = 0 },
          baby = { count = 3, item_loop = { {}, {}, {} } } }) })
    check("fallback order rg35xxh,baby", targets() == "rg35xxh,baby",
          "got " .. targets())
    check("baby entries rendered",
          type(rendered) == "table" and rendered.count == 3)
end

-- 2. rg35xxh entries present -> no fallback
do
    runMenu({ fakeServer("repo", false,
        { rg35xxh = { count = 2, item_loop = { {}, {} } } }) })
    check("no fallback when platform entries exist",
          targets() == "rg35xxh", "got " .. targets())
    check("platform entries rendered",
          type(rendered) == "table" and rendered.count == 2)
end

-- 3. nothing anywhere (+SN present) -> SN queried last, empty render
do
    runMenu({ fakeServer("repo", false, {}),
              fakeServer("sn", true, {}) })
    check("SN queried last", targets() == "rg35xxh,baby,rg35xxh",
          "got " .. targets())
    check("empty render",
          type(rendered) == "table" and rendered.count == 0)
end

if failures > 0 then
    os.exit(1)
end
print("applet target fallback: all green")
