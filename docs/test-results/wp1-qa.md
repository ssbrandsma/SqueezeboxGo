# WP1 QA results

Date: 2026-11-15 20:04 UTC. Branch: `wp1/qa`. Commit: `a759228` (gates re-run clean on this tree; baseline `7b2464e`).
Host: `DESKTOP-OVMHVD2` (Linux x86_64).

## Summary

| Check | Status | Notes |
|---|---|---|
| shellcheck-full | BLOCKED | shellcheck binary not installed on host; gate used bash -n fallback |
| arch | NOT RUN | no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet) |
| asound | NOT RUN | no ALSA configs under audio/alsa/ yet |
| diffoscope | NOT RUN | no build artifacts yet; diffoscope not installed |
| hardware-alsa | NOT RUN | no physical RG35XX H access yet |
| hardware-display | NOT RUN | no physical RG35XX H access yet |
| hardware-evdev | NOT RUN | no physical RG35XX H access yet |
| mapping | NOT RUN | no mapping files under ui/input/ yet |
| skin | NOT RUN | no skin manifests under ui/skins/ yet |
| checksum-tooling | PASS | releases/checksum.sh create+verify OK on scratch dir |
| repro:env | PASS | SOURCE_DATE_EPOCH=1794772822 ok |
| selftest | PASS | harness self-test 20/20 on fixtures (tests/selftest.sh) |
| shellcheck | PASS | checksum.sh: syntax ok [bash -n (shellcheck not installed)] |

Totals — PASS: 4, NOT RUN: 8, BLOCKED: 1.

## Details

### shellcheck-full — BLOCKED

Target: `manual`

```
shellcheck binary not installed on host; gate used bash -n fallback
```

### arch — NOT RUN

```
no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet)
```

### asound — NOT RUN

```
no ALSA configs under audio/alsa/ yet
```

### diffoscope — NOT RUN

Target: `manual`

```
no build artifacts yet; diffoscope not installed
```

### hardware-alsa — NOT RUN

Target: `manual`

```
no physical RG35XX H access yet
```

### hardware-display — NOT RUN

Target: `manual`

```
no physical RG35XX H access yet
```

### hardware-evdev — NOT RUN

Target: `manual`

```
no physical RG35XX H access yet
```

### mapping — NOT RUN

```
no mapping files under ui/input/ yet
```

### skin — NOT RUN

```
no skin manifests under ui/skins/ yet
```

### checksum-tooling — PASS

Target: `manual`

```
releases/checksum.sh create+verify OK on scratch dir
```

### repro:env — PASS

```
SOURCE_DATE_EPOCH=1794772822 ok
```

### selftest — PASS

Target: `manual`

```
harness self-test 20/20 on fixtures (tests/selftest.sh)
```

### shellcheck — PASS

```
checksum.sh: syntax ok [bash -n (shellcheck not installed)]
build-and-check.sh: syntax ok [bash -n (shellcheck not installed)]
run_shellcheck.sh: syntax ok [bash -n (shellcheck not installed)]
selftest.sh: syntax ok [bash -n (shellcheck not installed)]
note: install shellcheck for full lint; fallback is syntax-only
checked 4 script(s) with bash -n (shellcheck not installed)
```

## Evidence (real output, observed 2026-11-15)

Harness self-test (`bash tests/selftest.sh`):

```text
selftest: 20 passed, 0 failed
```

Full gate run on the baseline tree
(`SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) scripts/build-and-check.sh`):

```text
gate arch: NOT RUN
gate asound: NOT RUN
gate mapping: NOT RUN
gate skin: NOT RUN
gate shellcheck: PASS
gate repro-env: PASS
result counts: {'NOT RUN': 4, 'PASS': 2}
```

Arch-validator host oracle (proves allowlist logic on a real ELF):

```text
$ python3 tests/check_arch.py --expect x86-64 --interp '' /bin/true
[...] arch ok ... NEEDED ok: libc.so.6 ... [RESULT] arch: PASS        (exit 0)
$ python3 tests/check_arch.py --expect aarch64 --interp '' /bin/true
[...] ARCH MISMATCH ... [RESULT] arch: FAIL                           (exit 1)
```

Release checksum tooling on a scratch dir (outside git):

```text
$ bash releases/checksum.sh create /tmp/rel-demo
8b4d2898...  MANIFEST.json
b46e41f2...  demo.img.xz
$ bash releases/checksum.sh verify /tmp/rel-demo
MANIFEST.json: OK
demo.img.xz: OK
```

Reproducibility manifest round-trip (`check_repro manifest` + `compare`):
covered by selftest (identical manifests PASS, changed file FAIL).

## How to reproduce

```sh
bash tests/selftest.sh            # harness proves itself on fixtures: 20/20
scripts/build-and-check.sh        # full gate run + regenerates this report
```
