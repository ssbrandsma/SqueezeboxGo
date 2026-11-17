# Overnight Standalone Radio E2E — evidence (2026-11-16/17)

Device: RG35XX H V4.0, stock Ubuntu 22.04 / kernel 4.9.170 / glibc 2.35.
SqueezeboxGo 0.2.8 (`SqueezeboxGo-0.2.8-stockos-rg35xxh.zip`
sha256 `049f8aec97b8f028ade19b6f07cf8dd14a843d2b73098f09e7f59afbabadeb5d`),
deployed + launched via App Center entry from SSH.

## Chain verified live

- Jive 9.0.0 r541 fullscreen 640x480x32 (SDL/fbcon), RG35XXHLandscapeSkin.
- StandaloneRadio 0.9.20 (26 entries, 92645 bytes) loads via json.lua
  cjson bridge (`require 'json'` satisfied; HlsMetadata no longer loops).
- Popular list populates via nslookup PATH shim (Resolver shells out;
  stock has no nslookup). NPO Radio 1, Radio 538 visible, navigable.
- Play: AAC decode + ICY metadata in log, PCM `RUNNING` on
  `plughw:CARD=audiocodec,DEV=0` S16_LE, stream to 145.58.50.39:80
  flowing (bytes_received advancing every sample).

## 10-minute soak (0.2.8 playing session, untouched 540s)

- T=6226.84: PCM RUNNING hw_ptr 6522253, bytes_received 657591,
  XRUN 0, JIVE ALIVE.
- T=6767.02: PCM RUNNING hw_ptr 30345290, bytes_received 2814894,
  XRUN 0, JIVE ALIVE.
- hw_ptr delta 23823037 frames / 540.18s = 44100 Hz EXACT — real
  audio flowing through jive_alsa for the full soak. Stream bytes
  +2157303. Zero XRUNs. Soak: GREEN.

## Colors (0.2.8 explicit-fields preset)

- Language screen: WHITE (0xff/0x00 pure).
- Popular screen: WHITE (0xff/0x00 pure).
- End-of-soak screen: WHITE Popular list, clock live (2:59AM).
- Root cause closed: SDL read stale fb var bitfields (green-negative
  proof) / inherited fields per window (tint lottery); preset now
  writes explicit RGB fields before SDL init. Deterministic WHITE
  across 3 windows (Language, Popular, Popular+9min).
- Overnight park: Jive SIGKILLed (ignores SIGTERM), dmenu BACK,
  fb0 restored 1280x1024, /tmp locks released + tmp cleaned.

## Gates (host, this session)

- go-app-package: 122/122 PASS.
- sysv-shim: 3/3 (shm share + stderr silent).
- input: 16/16.
- selftest: 27/27.

## Commits

- `aada1e2` SqueezeboxGo 0.2.8 code (fb-preset + VERSION + tests).
- Status/evidence commit follows soak.

## Pending user (morning)

1. Ears-check: Radio audible from speakers/headphones?
2. Tap-through 0.2.8 (fresh eyes on colors + Radio play).
3. Standalone Base source location.
4. Release west-chromosphere + saffron-mintaka from hold.
