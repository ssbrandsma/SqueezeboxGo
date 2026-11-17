-- SqueezeboxGo default logconf (seeded into userpath on first launch).
-- Jive dies silently when userpath/logconf.lua is missing (proven on
-- device 2026-11-16), so launch.sh copies this in with cp -n.
-- Shape mirrors the proven staging config; INFO keeps App Center
-- logs useful without the full DEBUG flood.
return {
  appender={ stdout="INFO" },
  category={
    ["audio.codec"]="INFO",
    ["audio.decode"]="INFO",
    ["audio.output"]="INFO",
    ["squeezeplay"]="INFO",
    ["squeezeplay.ui"]="INFO",
    ["squeezeplay.ui.draw"]="INFO",
    -- Unlisted categories default to OFF (even errors vanish), so the
    -- operationally critical ones are named: applet manager/installer
    -- activity and HTTP client errors (proven blind spots 2026-11-16).
    ["squeezeplay.applets"]="INFO",
    ["net.http"]="WARN"
  }
}
