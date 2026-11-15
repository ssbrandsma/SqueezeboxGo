# WP2 Standalone test results (2026-11-15, branch `wp2/standalone`)

Owner: Agent 5. Cross-tree note: this file lives in Agent 6's
`docs/test-results/` tree; written here because the WP2 task explicitly
requires Standalone evidence at this path.
Code commit: `ac30c45` ("[standalone] WP2: wire adapters to real
audio-owner, systemd proposal, backend plan"). Base: main @ `96217b5`.
Host: Linux x86_64 (`flock` util-linux 2.39.3, python3 3.12.3,
systemd-analyze 255). The real arbiter `audio/arbiter/audio-owner`
was used read-only; no files outside `standalone/` were modified
except this evidence file.

## 1. Arbiter integration (`standalone/tests/test-arbiter-integration.sh`)

43/43 pass on host against the REAL arbiter (env-pointed via
`AUDIO_OWNER_BIN` + `AUDIO_OWNER_DIR` under mktemp; no root):

- Client passthrough: status free→exit 3, acquire→0, second
  acquire→1 (held-by-other), release by non-holder→5,
  release holder→0, wait on free→0, usage error→1.
- Adapter start binds the claim to the backend pid
  (`status` → `held source=demo pid=<backend-pid>`); start publishes
  `source_id=demo mode=play`.
- Second source while held: start fails (rc=1), loser backend
  stopped with no survivor, first source keeps the claim.
- Adapter stop: arbiter `free`, `mode=stop` published.
- Crash recovery: SIGKILLed backend reaps on next acquire
  (`event=reaped source=demo`); adapter stop after crash exits 0.
- All 8 stubs (music, proxy, qobuz, radio, spotify, squeezeplay,
  vpn, webui): adapter start fails with the arbiter untouched, and
  each backend exits 3 with `UNIMPLEMENTED` contract text (16 checks).
- `arbiter-event-np.sh`: acquired→source+play; released for another
  source→no clobber; reaped for current→mode=stop; timeout/garbage
  lines ignored.
- Publisher smoke: adversarial values
  (`Comma, "Quote" \ Backslash`) round-trip through `json.load`.

Observed tail:

```
ok 43 - publisher JSON round-trips adversarial values
---
pass=43 fail=0 total=43
```

Behavioral fix vs WP1: adapter `start` now starts the backend first
and claims with `--pid <backend-pid>`. Claiming as the short-lived
adapter shell (WP1 order) would go stale on return and allow a
double-hold; verified live claim pid == backend pid (test 11).

## 2. Static checks — observed

- `bash -n` over `standalone/base/*.sh`,
  `standalone/integration/*.sh`, `standalone/tests/*.sh`: all clean.
- shellcheck/luac: not installed on host — not run (same as WP1).
- `systemd-analyze verify` on `squeezebox-source@test.service` +
  `squeezebox-standalone.target` with target paths rewritten to a
  staging dir: clean (`UNITS-VERIFY-OK`). Unrewritten units reference
  target-only paths, so host verify of the raw files is not
  meaningful; the rewrite diff is path prefixes only.
- Repo `tests/selftest.sh`: 20 passed, 0 failed (no regressions).

## 3. systemd proposal (`standalone/systemd/`)

Template unit `squeezebox-source@.service` (oneshot +
RemainAfterExit, mirroring `wifi.service`) + grouping target
`squeezebox-standalone.target`, in platform-overlay layout with an
install-mapping README for the platform agent. Enable policy: ship
disabled — all 8 backends are UNIMPLEMENTED, so no instance is
enabled by default; trial `systemctl start squeezebox-source@radio`
fails honestly (adapter rc=1, backend exit 3, no state touched).

## 4. Backend evaluation (`standalone/BACKEND_PLAN.md`)

Public sources only; no backend code copied into git (one throwaway
`/tmp` clone for tag inspection, deleted):

- librespot **v0.8.0** (`d36f9f19`, 2025-11-10), MIT, rust 1.85,
  `alsa-backend` feature present, CLI `--backend`/`--device` options
  confirmed in `src/main.rs`. Draft WP3 build plan recorded.
- **Pin correction:** `ralph-irving/slimserver` 404s publicly
  (HTTPS 404 + `git ls-remote` failure, verified 2026-11-15); do not
  vendor from it. Replacement candidate `lms-community/slimserver`
  tag 9.0.2 = commit `1470c941…`. Needs Lead approval to re-pin.
- OpenVPN 2.5.11 carried as WP1 reference (not re-fetched);
  webui/proxy/squeezeplay-command unchanged (no upstream / other
  owner). No backend APIs invented: runtime flags beyond confirmed
  option names are TBD after vendoring.

## 5. Not covered (needs other agents / WP3)

- On-target run (aarch64 image does not exist yet); host-only runs.
- Real backends behind the adapters (librespot build, slimserver
  plugins) — WP3 per BACKEND_PLAN.md.
- Platform integration of the systemd proposal (Agent 1 decision).
