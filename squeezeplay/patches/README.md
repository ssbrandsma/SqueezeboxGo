# Patches against squeezeplay@758bc11 (Agent 2, Core)

Small reviewable patches; the upstream tree itself is never committed here
(see `../upstream/vendor-notes.md`). Audio-owned patches, if any, are
coordinated with Agent 3 per AGENTS.md.

WP2 promotion: 0004–0006 promote Agent 3's `audio/alsa/proposals/0001–0003`
(reviewed by Agent 2 against the pinned tree; review notes in each header
and in `docs/test-results/wp2-core.md`). All three accepted, none rejected.

Apply from the upstream repo root (`/tmp/wp1-core/squeezeplay`):

```sh
for p in <tree>/squeezeplay/patches/000*.patch; do
  patch -p1 < "$p"
done
```

Or via quilt/stgit with the `series` file.

| # | File | Against | Purpose |
|---|---|---|---|
| 0001 | `0001-lua-5.1.5-sharedlib-aarch64-rg35xxh.patch` | `src/lua-5.1.5` | PUC Lua shared-lib recipe adapted from tcz-jivelite, retuned cortex-a72→a53, rpath `/opt/squeezeplay/lib`, no readline/ncurses; arch flags overridable via `LUA_ARCHFLAGS?=` |
| 0002 | `0002-squeezeplay-git-revcount-version.patch` | `src/squeezeplay/Makefile.{am,in}` | `version.h`: revision from `git rev-list HEAD --count` (svnversion/unknown fallback); release overridable via `SQUEEZEPLAY_RELEASE` (default: `squeezeplay.version`) |
| 0003 | `0003-squeezeplay-jive-link-libm.patch` | `src/squeezeplay/Makefile.{am.in}` | link `jive` and `jive_alsa` with `-lm`: modern ld errors (`DSO missing`) without it; affects native and cross builds alike |
| 0004 | `0004-jive-alsa-log-negotiated-pcm-params.patch` | `src/squeezeplay/.../decode_alsa_backend.c` | (audio proposal 0001) `LOG_INFO` one line per successful `_pcm_open`: device, format, rate, access, period/buffer frames |
| 0005 | `0005-jive-alsa-clamp-buffer-params.patch` | `src/squeezeplay/.../decode_alsa_backend.c` | (audio proposal 0002) fail-soft clamp `buffer_time` 5…500 ms → 30000, `period_count` 2…16 → 3, with `LOG_WARN` |
| 0006 | `0006-decode-alsa-audio-owner-hook.patch` | `src/squeezeplay/.../decode_alsa.c` | (audio proposal 0003) opt-in `audio-owner acquire/release` around playback fork when `AUDIO_OWNER_BIN` set; init returns 0 (clean fallback) when held |
| 0007 | `0007-jive-framework-public-event-queue-length.patch` | `src/squeezeplay/.../ui/jive_framework.c` | (integrator, needs Agent 2 review) perfwarn queue check via public `SDL_PeepEvents` count instead of internal `SDL_EventQueueLength` (unexported by sdl12-compat; broke jive startup under BIND_NOW) |

Notes:
- Patch 0001 intentionally leaves `luac` statically linked (no runtime
  `liblua.so` dependency for the compiler binary); the `lua` interpreter
  links the shared lib, as in the tcz recipe.
- `Makefile.am` and `Makefile.in` are patched together because the build
  consumes the shipped `Makefile.in` directly (no automake re-run).
- Upstream's loose `lua-nosharedlibrary.patch` is for static-only
  squeezeos builds and is NOT used here.
