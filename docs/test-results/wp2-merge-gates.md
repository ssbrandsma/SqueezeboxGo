# WP1 QA results

Date: 2026-11-15 21:20 UTC. Branch: `main`. Commit: `16d068a`.
Host: `DESKTOP-OVMHVD2` (Linux x86_64).

## Summary

| Check | Status | Notes |
|---|---|---|
| arch | NOT RUN | no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet) |
| asound | PASS | audio/alsa/asound.conf: syntax ok |
| image | PASS | ../../../../tmp/squeezebox-rg35xxh-ddr4.img: 2147483648 bytes (2048.0 MiB) |
| mapping | PASS | ui/input/rg35xxh.map: mapping ok |
| repro:env | PASS | SOURCE_DATE_EPOCH=1794777547 ok |
| shellcheck | PASS | capability-detect.sh: syntax ok [bash -n (shellcheck not installed)] |
| skin | PASS | ui/skins/RG35XXHBaseSkin: lua skin ok |

Totals — PASS: 6, NOT RUN: 1.

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

### image — PASS

```
../../../../tmp/squeezebox-rg35xxh-ddr4.img: 2147483648 bytes (2048.0 MiB)
protective MBR ok (0xEE, boot sig)
GPT primary header CRC ok
GPT array at sunxi LBA 4096 ok
GPT primary array CRC ok
p1 BOOT: 32768..557055 ok
p2 ROOTFS: 557056..4194271 ok
GPT backup header ok
SPL blob present at sector 16
../../../../tmp/squeezebox-rg35xxh-ddr4.img: boot file present: BOOT.SCR
../../../../tmp/squeezebox-rg35xxh-ddr4.img: boot file present: IMAGE
../../../../tmp/squeezebox-rg35xxh-ddr4.img: boot file present: DTB.IMG
no-secrets scan clean
checked 1 target(s), 0 problem(s)
```

### mapping — PASS

```
ui/input/rg35xxh.map: mapping ok
checked 1 file(s), 0 failed
```

### repro:env — PASS

```
SOURCE_DATE_EPOCH=1794777547 ok
```

### shellcheck — PASS

```
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
arbiter-event-np.sh: syntax ok [bash -n (shellcheck not installed)]
audio-owner-client.sh: syntax ok [bash -n (shellcheck not installed)]
nowplaying-pub.sh: syntax ok [bash -n (shellcheck not installed)]
service.sh: syntax ok [bash -n (shellcheck not installed)]
unimplemented.sh: syntax ok [bash -n (shellcheck not installed)]
web-routes.sh: syntax ok [bash -n (shellcheck not installed)]
test-arbiter-integration.sh: syntax ok [bash -n (shellcheck not installed)]
run_shellcheck.sh: syntax ok [bash -n (shellcheck not installed)]
selftest.sh: syntax ok [bash -n (shellcheck not installed)]
run_tests.sh: syntax ok [bash -n (shellcheck not installed)]
install.sh: syntax ok [bash -n (shellcheck not installed)]
init-splash.sh: syntax ok [bash -n (shellcheck not installed)]
fetch-sdl12-compat.sh: syntax ok [bash -n (shellcheck not installed)]
note: install shellcheck for full lint; fallback is syntax-only
checked 33 script(s) with bash -n (shellcheck not installed)
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
