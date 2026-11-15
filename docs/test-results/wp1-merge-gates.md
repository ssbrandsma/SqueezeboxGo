# WP1 QA results

Date: 2026-11-15 20:42 UTC. Branch: `main`. Commit: `f25cd41`.
Host: `DESKTOP-OVMHVD2` (Linux x86_64).

## Summary

| Check | Status | Notes |
|---|---|---|
| arch | NOT RUN | no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet) |
| asound | PASS | audio/alsa/asound.conf: syntax ok |
| mapping | PASS | ui/input/rg35xxh.map: mapping ok |
| repro:env | PASS | SOURCE_DATE_EPOCH=1794775250 ok |
| shellcheck | PASS | build.sh: syntax ok [bash -n (shellcheck not installed)] |
| skin | PASS | ui/skins/RG35XXHBaseSkin: lua skin ok |

Totals — PASS: 5, NOT RUN: 1.

## Details

### arch — NOT RUN

```
no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet)
```

### asound — PASS

```
audio/alsa/asound.conf: syntax ok
audio/alsa/asound.conf: syntax ok
checked 2 file(s), 0 failed
```

### mapping — PASS

```
ui/input/rg35xxh.map: mapping ok
checked 1 file(s), 0 failed
```

### repro:env — PASS

```
SOURCE_DATE_EPOCH=1794775250 ok
```

### shellcheck — PASS

```
build.sh: syntax ok [bash -n (shellcheck not installed)]
assemble-image.sh: syntax ok [bash -n (shellcheck not installed)]
build-kernel.sh: syntax ok [bash -n (shellcheck not installed)]
build-uboot.sh: syntax ok [bash -n (shellcheck not installed)]
fetch.sh: syntax ok [bash -n (shellcheck not installed)]
fetch-oot.sh: syntax ok [bash -n (shellcheck not installed)]
mkrootfs.sh: syntax ok [bash -n (shellcheck not installed)]
splash.sh: syntax ok [bash -n (shellcheck not installed)]
squeezeplay.sh: syntax ok [bash -n (shellcheck not installed)]
wifi.sh: syntax ok [bash -n (shellcheck not installed)]
build-native-deps.sh: syntax ok [bash -n (shellcheck not installed)]
capability-detect.sh: syntax ok [bash -n (shellcheck not installed)]
pcm-format-matrix.sh: syntax ok [bash -n (shellcheck not installed)]
run-all.sh: syntax ok [bash -n (shellcheck not installed)]
topology-probe.sh: syntax ok [bash -n (shellcheck not installed)]
underrun-recovery-test.sh: syntax ok [bash -n (shellcheck not installed)]
usb-hotplug-fallback.sh: syntax ok [bash -n (shellcheck not installed)]
run_tests.sh: syntax ok [bash -n (shellcheck not installed)]
init-splash.sh: syntax ok [bash -n (shellcheck not installed)]
fetch-sdl12-compat.sh: syntax ok [bash -n (shellcheck not installed)]
adapter.sh: syntax ok [bash -n (shellcheck not installed)]
audio-owner-client.sh: syntax ok [bash -n (shellcheck not installed)]
nowplaying-pub.sh: syntax ok [bash -n (shellcheck not installed)]
service.sh: syntax ok [bash -n (shellcheck not installed)]
unimplemented.sh: syntax ok [bash -n (shellcheck not installed)]
web-routes.sh: syntax ok [bash -n (shellcheck not installed)]
checksum.sh: syntax ok [bash -n (shellcheck not installed)]
build-and-check.sh: syntax ok [bash -n (shellcheck not installed)]
run_shellcheck.sh: syntax ok [bash -n (shellcheck not installed)]
selftest.sh: syntax ok [bash -n (shellcheck not installed)]
capability-detect.sh: syntax ok [bash -n (shellcheck not installed)]
pcm-format-matrix.sh: syntax ok [bash -n (shellcheck not installed)]
run-all.sh: syntax ok [bash -n (shellcheck not installed)]
topology-probe.sh: syntax ok [bash -n (shellcheck not installed)]
underrun-recovery-test.sh: syntax ok [bash -n (shellcheck not installed)]
usb-hotplug-fallback.sh: syntax ok [bash -n (shellcheck not installed)]
build.sh: syntax ok [bash -n (shellcheck not installed)]
assemble-image.sh: syntax ok [bash -n (shellcheck not installed)]
build-native-deps.sh: syntax ok [bash -n (shellcheck not installed)]
build-kernel.sh: syntax ok [bash -n (shellcheck not installed)]
build-uboot.sh: syntax ok [bash -n (shellcheck not installed)]
fetch.sh: syntax ok [bash -n (shellcheck not installed)]
fetch-oot.sh: syntax ok [bash -n (shellcheck not installed)]
mkrootfs.sh: syntax ok [bash -n (shellcheck not installed)]
splash.sh: syntax ok [bash -n (shellcheck not installed)]
squeezeplay.sh: syntax ok [bash -n (shellcheck not installed)]
wifi.sh: syntax ok [bash -n (shellcheck not installed)]
checksum.sh: syntax ok [bash -n (shellcheck not installed)]
build-and-check.sh: syntax ok [bash -n (shellcheck not installed)]
adapter.sh: syntax ok [bash -n (shellcheck not installed)]
audio-owner-client.sh: syntax ok [bash -n (shellcheck not installed)]
nowplaying-pub.sh: syntax ok [bash -n (shellcheck not installed)]
service.sh: syntax ok [bash -n (shellcheck not installed)]
unimplemented.sh: syntax ok [bash -n (shellcheck not installed)]
web-routes.sh: syntax ok [bash -n (shellcheck not installed)]
run_shellcheck.sh: syntax ok [bash -n (shellcheck not installed)]
selftest.sh: syntax ok [bash -n (shellcheck not installed)]
run_tests.sh: syntax ok [bash -n (shellcheck not installed)]
init-splash.sh: syntax ok [bash -n (shellcheck not installed)]
fetch-sdl12-compat.sh: syntax ok [bash -n (shellcheck not installed)]
note: install shellcheck for full lint; fallback is syntax-only
checked 60 script(s) with bash -n (shellcheck not installed)
```

### skin — PASS

```
ui/skins/RG35XXHBaseSkin: lua skin ok
ui/skins/RG35XXHBaseSkin: 300 PNG(s) checked, 300 ok (16 oversize-but-legal)
ui/skins/RG35XXHBaseSkin: 2 Lua file(s) compile ok
ui/skins/RG35XXHLandscapeSkin: lua skin ok
ui/skins/RG35XXHLandscapeSkin: 167 PNG(s) checked, 167 ok (11 oversize-but-legal)
ui/skins/RG35XXHLandscapeSkin: 2 Lua file(s) compile ok
checked 2 skin(s), 0 failed
```
