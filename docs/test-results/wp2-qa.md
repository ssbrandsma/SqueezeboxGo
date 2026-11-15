# WP2 QA results

Date: 2026-11-15 20:47 UTC. Branch: `wp2/qa`. Commit: `96217b5`.
Host: `DESKTOP-OVMHVD2` (Linux x86_64).

## Summary

| Check | Status | Notes |
|---|---|---|
| arch | NOT RUN | no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet) |
| image | NOT RUN | no .img under build/out/ and $IMAGE_UNDER_TEST unset (assemble first: build/image/assemble-image.sh) |
| asound | PASS | audio/alsa/asound.conf: syntax ok |
| mapping | PASS | ui/input/rg35xxh.map: mapping ok |
| repro:env | PASS | SOURCE_DATE_EPOCH=1794775391 ok |
| shellcheck | PASS | capability-detect.sh: syntax ok [bash -n (shellcheck not installed)] |
| skin | PASS | ui/skins/RG35XXHBaseSkin: lua skin ok |

Totals — PASS: 5, NOT RUN: 2.

## Details

### arch — NOT RUN

```
no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet)
```

### image — NOT RUN

```
no .img under build/out/ and $IMAGE_UNDER_TEST unset (assemble first: build/image/assemble-image.sh)
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
SOURCE_DATE_EPOCH=1794775391 ok
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
checked 30 script(s) with bash -n (shellcheck not installed)
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

## Supplementary evidence (WP2 QA branch work)

### Harness self-test — PASS (27/27)

`bash tests/selftest.sh` → `selftest: 27 passed, 0 failed` (WP1: 20;
+7 new image-gate cases: good/bad tree, empty-root NOT RUN, missing
target BLOCKED, synthetic GPT skeleton PASS via the real
`build/image/mksunxi_gpt.py` writer, corrupted-GPT FAIL,
`IMAGE_UNDER_TEST` env honored).

### Image gate verification — PASS

`tests/check_image.py` (new) exercised beyond the self-test, on scratch
images in `$TMPDIR` only (never committed, never flashed):

- Tree mode: `tests/fixtures/image-good` → PASS (boot.scr, Image,
  `sun50i-h700-anbernic-rg35xx-h.dtb`, `etc/os-release`, secrets clean);
  `tests/fixtures/image-bad` → FAIL (missing DTB + fixture PEM marker
  in `leaked-key.txt` detected).
- Raw `.img` mode: 512 MiB skeleton from `mksunxi_gpt.py` + fake SPL at
  sector 16 + hand-staged FAT32 root (BOOT.SCR, IMAGE, DTB.IMG) →
  full PASS incl. protective MBR, GPT header/array CRCs, p1/p2
  start-size-type, backup header, SPL present, FAT boot-file listing,
  no-secrets scan.
- Negatives, each → FAIL with a named PROBLEM: zeroed MBR+SPL,
  embedded `-----BEGIN RSA PRIVATE KEY-----` marker, `--max-mb`
  violation. Missing target → BLOCKED (exit 4); no images →
  NOT RUN (exit 3).
- Host lacks `mkfs.vfat`/`mcopy`/`sfdisk`, so end-to-end validation
  against a real `assemble-image.sh` output is NOT RUN until the
  container build exists; the pure-python GPT+FAT parsers above are the
  coverage until then.

### Release tooling — PASS

- `releases/MANIFEST.example.json`: valid JSON, 3 artifacts, TBD
  placeholders for sha256/size_bytes (recorded when the image exists).
- `releases/checksum.sh create|verify` unchanged from WP1 (PASS there).

### Manual gates — NOT RUN (no hardware yet)

| Check | Status | Notes |
|---|---|---|
| hardware-boot (H1–H2) | NOT RUN | no physical RG35XX H access yet; see HW_TEST_PLAN.md |
| hardware-display/input/audio/wifi/battery (H3–H18) | NOT RUN | same; matrix + UART/SSH procedure ready |
| diffoscope rebuild-twice | NOT RUN | no build artifacts yet |

### New/changed files (this branch)

- `tests/check_image.py`, `tests/fixtures/image-good/*`,
  `tests/fixtures/image-bad/*`, `tests/selftest.sh` (+7),
  `tests/README.md` (gate row)
- `scripts/build-and-check.sh` (image gate, `--title`, `IMAGE_UNDER_TEST`)
- `docs/test-results/HW_TEST_PLAN.md` (new), `docs/test-results/wp2-qa.md`
- `releases/RELEASE-CHECKLIST.md` (new), `releases/MANIFEST.example.json`

## How to reproduce

```sh
bash tests/selftest.sh            # expect: 27 passed, 0 failed
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
scripts/build-and-check.sh --report docs/test-results/wp2-qa.md --title "WP2 QA results"
python3 tests/check_image.py path/to/squeezebox-rg35xx-h-<variant>.img  # when built
```
