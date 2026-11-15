# QA checks (Agent 6) — host-runnable, stdlib-only

Every check follows one contract:

| Status | Meaning | Exit |
|---|---|---|
| PASS | all targets satisfied the check | 0 |
| FAIL | at least one target violated the check | 1 |
| ERROR | the check itself crashed (bug) | 2 |
| NOT RUN | no targets exist yet (greenfield) | 3 |
| BLOCKED | required tool/input missing | 4 |

`NOT RUN` and `BLOCKED` are honest non-results, never silent passes:
CI gates treat FAIL/ERROR as red, PASS as green, and report the rest.

## Checks

| Check | Command | Targets |
|---|---|---|
| arch (ELF machine + NEEDED allowlist) | `python3 tests/check_arch.py [--expect aarch64\|x86-64] [paths...]` | ELF files under `build/ platform/ squeezeplay/ standalone/ ui/ audio/` |
| asound (ALSA syntax) | `python3 tests/check_asound.py [files...]` | `audio/alsa/**` |
| mapping (input bindings) | `python3 tests/check_mapping.py [files...]` | `ui/input/*.{json,conf,map}` |
| skin (640x480 = 2x QVGA) | `python3 tests/check_skin.py [manifests...]` | `ui/skins/*/skin.json` |
| shellcheck (or `bash -n` fallback) | `bash tests/run_shellcheck.sh [dirs...]` | `**/*.sh` except `tests/fixtures/` |
| repro env | `python3 tests/check_repro.py env` | `$SOURCE_DATE_EPOCH` |
| repro manifest | `python3 tests/check_repro.py manifest DIR -o OUT` | any dir |
| repro compare | `python3 tests/check_repro.py compare A B` | two manifests |
| image (GPT + boot files + secrets + size) | `python3 tests/check_image.py [--skip-bootfs] [IMG-or-DIR...]` | `build/out/*.img`, `$IMAGE_UNDER_TEST`, or explicit paths |

All Python checks accept `--root DIR` and `--json` (single JSON object
`{"check","status","target","details"}` for the report generator).

## Dependencies

`file`, `readelf`, `sha256sum`, `python3` (>= 3.8), `bash`.
`shellcheck` optional — the gate falls back to `bash -n` and says so.
`diffoscope` optional — used only for manual rebuild-twice inspection.

## Harness self-test

`bash tests/selftest.sh` runs every check against positive + negative
fixtures in `tests/fixtures/` (exit 0 = harness healthy). PNG skin
fixtures are generated in `$TMPDIR` at runtime; git stays text-only.

## Schemas (v1, QA-proposed)

Mapping JSON: `{"device": "...", "bindings": {"<button>": "<Action>"}}`
with canonical actions from `docs/interface-contracts.md`:
Up/Down/Left/Right/Select/Back/NowPlaying/Favorites/PlayPause/Home/
Prev/Next/VolDown/VolUp (+ optional Scroll*/VolMute/Brightness*/Power).
Skin manifest: `{"name","width":640,"height":480,
"base":{"width":320,"height":240},"assets":[...]}`.
`.conf` mappings use `KEY=Action` lines. Agent 4 owns schema evolution;
propose changes via Lead, then update the validators.
