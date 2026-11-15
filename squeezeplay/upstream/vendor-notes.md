# Upstream vendor notes (WP1 Core)

Pinned sources are fetched to `/tmp` (never committed wholesale).
Baseline pins come from [upstream-manifest.md](../../docs/upstream-references/upstream-manifest.md).
Verified 2026-11-15 by Agent 2 (Core).

| Component | Repo | Pinned SHA | Date | revcount | Role |
|---|---|---|---|---|---|
| squeezeplay | github.com/ralph-irving/squeezeplay | `758bc110e16de4a61905e19d012a0ad25d97859b` | 2026-09-25 | 541 | UI+playback base |
| squeezeos-squeezeplay | github.com/ralph-irving/squeezeos-squeezeplay | `766b6a8b3c3c7722d586125b068b47facf9d4a77` | 2026-10-10 | 6078 | backports only |
| squeezelite | github.com/ralph-irving/squeezelite | `cc7ee7c0d00bd2aa691a574a7d429d5cd13c858b` | 2026-10-28 | 541 | audio/SlimProto ref |
| jivelite | github.com/ralph-irving/jivelite | `d43a20b1a0248925296e387e016b320b9785e7c4` | 2025-12-28 | 225 | aarch64 recipe ref |
| tcz-jivelite | github.com/ralph-irving/tcz-jivelite | `4bdf67799c0b336fe1a1b54017c3dcb87bc7c763` | 2025-03-25 | 100 | aarch64 patches ref |

Fetch recipe (mirrors `build/toolchain/build.sh`):

```sh
mkdir -p /tmp/wp1-core && cd /tmp/wp1-core
for spec in "squeezeplay 758bc11" "squeezeos-squeezeplay 766b6a8" \
    "squeezelite cc7ee7c" "jivelite d43a20b" "tcz-jivelite 4bdf677"; do
  set -- $spec
  [ -d "$1" ] || git clone "https://github.com/ralph-irving/$1" "$1"
  (cd "$1" && git checkout --quiet "$2" && git rev-parse HEAD)
done
```

Tree notes (squeezeplay@758bc11, `src/`):
- Deps: SDL-1.2.15, SDL_gfx-2.0.15, SDL_image-1.2.5, SDL_ttf-2.0.11,
  freetype-2.4.2, expat-2.0.1, libpng-1.2.59, jpeg-9d, zlib-1.2.11,
  lua-5.1.5 (PUC), lua-cjson-2.1.0, luaexpat-1.0.2, luafilesystem-1.2,
  luasocket-2.0.2, slnunicode-1.1, luazipfilter, luamd5, luaprofiler-2.0.2,
  loop-2.2-alpha, tolua++-1.0.92, fdk-aac-2.0.3, libogg-1.2.2, flac-1.2.1,
  libmad-0.15.1b (-10 and -11 tarballs), Tremor.
- Jive core: `squeezeplay/` (autotools, SDL>=1.2.10, ALSA backend
  `src/audio/decode/decode_alsa.c` + `decode_alsa_backend.c`),
  `squeezeplay_desktop/` (packaging + `squeezeplay.sh`),
  `squeezeplay_contrib/`, `luartmp-squeezeplay/`.
- `squeezeplay.version` = `9.0.0` (see patch 0002 for JIVE_VERSION handling).
