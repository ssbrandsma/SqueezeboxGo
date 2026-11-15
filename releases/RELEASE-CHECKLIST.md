# Experimental release checklist (first `.img`)

For the first WP2 experimental image. Every box needs evidence in
`docs/test-results/` before the artifacts leave the bench. Policy anchor:
**no images in git** — `*.img`, `*.img.xz`, `*.sha256` stay out of tree
(see [releases README](README.md)); only manifests, checksums-as-text in
results docs, and this checklist are committed.

## Build

- [ ] Clean worktree at the release commit (`git status` clean, SHA recorded).
- [ ] Container toolchain pinned per `docs/build.md`; `SOURCE_DATE_EPOCH`
      exported from the release commit (`git log -1 --format=%ct`).
- [ ] `build/image/assemble-image.sh --check-deps` green inside the container.
- [ ] Both variants assembled out of tree (`build/out/`):
      `squeezebox-rg35xx-h-ddr3.img`, `squeezebox-rg35xx-h-ddr4.img`.
- [ ] SBOM recorded per build contract (path + hash in MANIFEST.json).

## Validate (host gates)

- [ ] `bash tests/selftest.sh` — 26/26 (harness healthy).
- [ ] `scripts/build-and-check.sh` — no FAIL (image gate PASS per variant
      via `IMAGE_UNDER_TEST=...`, or explicit `check_image.py` runs pasted
      into the milestone report).
- [ ] `python3 tests/check_image.py <each .img>` — PASS (GPT, SPL, boot
      files, DTB, no-secrets, size). Paste output into the report.
- [ ] `releases/checksum.sh create` + `verify` on the staged release dir.

## Stage

- [ ] Release dir layout (outside git, e.g. `/tmp/rel-YYYYMMDD/`):
      `*.img.xz`, `MANIFEST.json` (from template, every field filled),
      `SHA256SUMS`.
- [ ] `MANIFEST.json` matches [MANIFEST.example.json](MANIFEST.example.json)
      shape: version, variant(s), date_utc, source_date_epoch, git_commit,
      toolchain, sbom, and per-artifact file/size_bytes/sha256.
- [ ] `sha256sum -c SHA256SUMS` green; paste SHA256SUMS into the report.
- [ ] Compressed size sanity: each `.img.xz` well under host/upload limits;
      record sizes.

## Hardware smoke (human, per HW_TEST_PLAN.md)

- [ ] Flashed with Etcher (validate on) or Rufus (DD mode); tool recorded.
- [ ] UART boot log captured to `boot-<variant>-<date>.txt`: SPL → U-Boot →
      kernel → UI, no panic. At least one variant boots to UI.
- [ ] SSH capture (`uname/dmesg/journal/os-release`) attached.
- [ ] Matrix H1–H18 filled PASS/FAIL/NOT RUN in `hw-<date>-<variant>.md`;
      FAILs triaged to owning agent with sha256 + log excerpt.
- [ ] No secrets in any committed log (passwords/AP keys redacted).

## Publish

- [ ] Artifacts uploaded; URL recorded in the milestone report.
- [ ] `docs/project-status.md` updated (image SHA256s, hardware verdict).
- [ ] Release tagged only after all boxes above are checked.

## Manifest example

[MANIFEST.example.json](MANIFEST.example.json) shows a filled manifest for
the first experimental image. `sha256`/`size_bytes` there are placeholders:
real checksums are recorded when the image exists (paste
`SHA256SUMS` + `check_image.py` output into `docs/test-results/wp2-qa.md`
or the dated `hw-*.md` result file).
