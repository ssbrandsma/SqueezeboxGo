# Releases

Policy: **no images in git.** `*.img`, `*.img.xz`, and `*.sha256` are
git-ignored (see `.gitignore`). This directory holds only:

- `MANIFEST.template.json` — per-release metadata filled at publish time.
- `checksum.sh` — create/verify `SHA256SUMS` for a release directory.
- `SHA256SUMS` examples are produced at release time, never committed.

## Publish flow (WP2+)

```sh
# 1. Build images out of tree, e.g. build/out/
# 2. Stage a release dir (outside git or untracked):
mkdir -p /tmp/rel && cp build/out/*.img.xz /tmp/rel/
# 3. Manifest + checksums:
cp releases/MANIFEST.template.json /tmp/rel/MANIFEST.json
# ... fill version/date/artifacts ...
bash releases/checksum.sh create /tmp/rel
bash releases/checksum.sh verify /tmp/rel
# 4. Upload /tmp/rel/* to the release host; record URL + hashes in
#    docs/test-results/ for that milestone.
```
