-- Phase 3 diagnostic: enable all C log categories (reversible, staging only)
return {
  appender={ stdout="DEBUG" },
  category={
    ["audio.codec"]="DEBUG",
    ["audio.decode"]="DEBUG",
    ["audio.output"]="DEBUG",
    ["squeezeplay"]="DEBUG",
    ["squeezeplay.ui"]="DEBUG",
    ["squeezeplay.ui.draw"]="DEBUG"
  }
}
