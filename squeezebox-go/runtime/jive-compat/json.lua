-- json.lua (SqueezeboxGo compat): luajson-compatible facade over cjson.
--
-- Some applets (e.g. StandaloneRadio's HlsMetadata) require("json")
-- (luajson, a SqueezeOS-era C module). Desktop SqueezePlay 9 ships
-- cjson only, so a bare require("json") fails and poisons every later
-- load ("loop or previous error"). launch.sh seeds this file into
-- userpath/ (first on Jive's package.path), restoring the module.
-- Only decode/encode/null are bridged (all observed uses); anything
-- fancier should vendor its own parser. Prefer fixing the applet to
-- require cjson directly; this bridge exists so existing zips run.
local cjson = require("cjson")

local M = {}

M.decode = cjson.decode
M.encode = cjson.encode
M.null = cjson.null

-- luajson affordances some callers probe for; no-ops by design.
function M.setOption() end
M.version = "cjson-bridge/1.0"

return M
