# <Title> — test results

Date: <YYYY-MM-DD HH:MM UTC>. Branch: `<branch>`. Commit: `<sha>`.
Host: `<hostname>` (<os> <arch>).

## Summary

| Check | Status | Notes |
|---|---|---|
| <check> | PASS \| FAIL \| NOT RUN \| BLOCKED | <one-line note> |

Totals — PASS: <n>, FAIL: <n>, NOT RUN: <n>, BLOCKED: <n>.

Status meanings:

- PASS — the check ran and all targets satisfied it.
- FAIL — the check ran and at least one target violated it (must fix).
- NOT RUN — no targets exist yet, or the gate does not apply on this host.
- BLOCKED — a required tool, file, or device is missing (name it).

## Details

### <check> — <STATUS>

Target: `<target or "manual">`

```text
<paste the check's real output here; trim to the decisive lines>
```

## How to reproduce

```sh
bash tests/selftest.sh            # harness proves itself on fixtures
scripts/build-and-check.sh        # full gate run + regenerates the report
```
