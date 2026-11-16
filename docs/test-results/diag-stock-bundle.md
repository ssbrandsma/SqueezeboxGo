# diag-stock-bundle — test results (track B3, host logic)

Date: 2026-11-16 12:02 UTC. Branch: `diag/stock-bundle`. Code commit: `955c3514317785bb9c210a752d8eb8cf802ec4fb`.
Host: `DESKTOP-OVMHVD2` (Linux 6.6.87.2-microsoft-standard-WSL2 x86_64, bash 5.2.21, dash = /bin/sh).

## Summary

| Check | Status | Notes |
|---|---|---|
| probe fixture run (11 sections + tarball + sha256) | PASS | canned /proc+/sys+/dev+/etc, fake tools, PSK redaction asserted |
| probe live host smoke (dash, real /proc) | PASS | 11 section files, tarball listed clean (no tar-err) |
| probe read-only (fixture roots untouched) | PASS | mtime-marker check, no writes outside OUT dir |
| bundle install dry-run + real install + receipt | PASS | temp dest only |
| bundle refusal cases (/, /etc, /usr, relative, dot-dot) | PASS | 5/5 refused with `[refuse]` |
| run-jive unit validation (missing/critical/injected) | PASS | refuses to guess; ssh.service + `foo;reboot` refused |
| run-jive binary-before-stop ordering | PASS | missing jive fails before any stop; dry-run touches nothing |
| restore flows (no-flag refusal, dry-runs, real --remove) | PASS | outside-allowlist --remove refused |
| syntax (bash -n x7, dash -n x2) | PASS | probe + lib-safety are dash-clean (stock /bin/sh) |
| shellcheck | NOT RUN | not installed on host; repo gate falls back to bash -n |
| device run (UART, stock Jammy, vendor 4.9.170) | NOT RUN | no agent device access; human procedure in stock/README.md |

Totals — PASS: 9, FAIL: 0, NOT RUN: 2, BLOCKED: 0.

## Details

### harness — PASS

Target: `stock/tests/test-stock-bundle.sh` (44 assertions, mktemp-isolated)

```text
stock bundle tests: 44 PASS, 0 FAIL
```

Sections: syntax 10 (bash -n x7 incl. the harness itself, dash -n x2,
set -u source check x1), probe fixtures 15 (exit 0, tarball+sha256,
11 section files, fixture-data presence, PSK redaction, PCM-holder
block, fixture untouched), install 7 (dry-run, real, 5 refusals),
run-jive 5, restore 5. shellcheck section SKIPped (tool absent).

### probe live host smoke — PASS

Target: `STOCK_PROBE_OUT=/tmp/probe-smoke sh stock/probe/stock-probe.sh`

```text
stock-probe: tarball: /tmp/probe-smoke/stock-probe-20261116T120149Z-DESKTOP-OVMHVD2.tar.gz
stock-probe: files: 11 section files
11            <- *.txt entries in tarball
clean: no tar-err in tarball
```

(Missing-device blocks record MISSING/ABSENT instead of failing, e.g.
`fbset`, `/dev/snd`, `nmcli` on this host. Tarball + dir removed after.)

### refusal spot-checks — PASS

```text
[refuse] refusing to operate on /
[refuse] system path refused (bundle lives outside system dirs): /etc/evil
[refuse] refusing to stop critical unit (console/ssh/net/login): ssh.service
[refuse] unit name has illegal characters (refusing injection): foo;reboot
[refuse] no frontend unit given. Identify it from YOUR probe tarball ...
[refuse] no jive binary found. ... Frontend untouched.
```

## Device procedure (human, NOT RUN here)

1. `sh stock-probe.sh` as root over UART → tarball home (`scp`).
2. Read 10/20/30/40/90 sections; fill `frontend-unit.txt`, confirm `jive-env.sh`.
3. `bash install.sh --dry-run`, install, `bash run-jive.sh --dry-run`, run.
4. `bash restore.sh --restart-frontend`; record observations in a dated
   copy of this file's device section.

## How to reproduce

```sh
bash stock/tests/test-stock-bundle.sh   # 44 PASS, 0 FAIL (no device, no root)
bash tests/selftest.sh                  # repo harness unaffected (no files touched outside stock/ + this file)
```
