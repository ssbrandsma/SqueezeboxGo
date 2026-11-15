# Standalone backend plan (WP2 evaluation, WP3 build)

Owner: Agent 5. Date: 2026-11-15. Scope: **evaluation from public
sources only** — versions, URLs, licenses, and build facts recorded
below; **no backend code copied into git**. One throwaway clone was
made to `/tmp` for tag/version inspection and deleted afterwards, per
the vendoring rule in `standalone/REQUIRED_SOURCES.md`. Lead approval
is required before any pin below becomes a build input.

## 1. Spotify backend: librespot (Spotify Connect)

- Upstream: `https://github.com/librespot-org/librespot`
- Evaluated tag: **v0.8.0** — commit
  `d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d`, tagged 2025-11-10
  ("Preparations for v0.8.0 (#1632)"). HEAD at evaluation time:
  `15e02e86c72d96dd39d548e3749f00abe39ffdde`. Verified via
  `git ls-remote --tags` + shallow tag clone, 2026-11-15.
- Version/license/toolchain (from the tag itself): crate version
  `0.8.0`, license **MIT** (`LICENSE`), `rust-version = "1.85"`,
  edition 2024.
- Audio facts (from the tag itself): `alsa-backend` Cargo feature
  exists (Linux; `librespot-playback/alsa-backend`); default backend
  is `rodio-backend`. `COMPILING.md` recommends a `rustls-tls`
  feature for cross-compiling to avoid OpenSSL build complexity.
  The CLI defines `--backend` / `--device` options (`src/main.rs`
  option constants, v0.8.0).
- WP3 build plan (draft, no code yet):
  1. Fetch the pinned tag tarball to `/tmp` (never wholesale into
     git); verify the commit hash above.
  2. `cargo build --release` for the glibc aarch64 target matching
     the build contract (`aarch64-linux-gnu`), with a feature set
     along the lines of `alsa-backend` + one `rustls-tls` variant —
     exact set decided after a trial build, not guessed here.
  3. Rust toolchain ≥ 1.85, pinned; `cargo vendor` the dependency
     closure for offline/reproducible builds + SBOM (build contract).
  4. Runtime wiring (`backend.conf` `BACKEND_CMD`, audio-owner claim
     discipline, Now Playing mapping) is written **after** the source
     is vendored, against the real CLI — no flags are recorded as
     fact in this plan beyond the option names above.

Legacy `libspotify` stays dead: do NOT pursue (see REQUIRED_SOURCES
item 9).

## 2. Radio / Music / Qobuz backends: slimserver plugins

- **Pin correction.** `REQUIRED_SOURCES.md` item 7 cites
  `github.com/ralph-irving/slimserver.git;tag=9.0.2` from
  `squeezeos.conf`. That repository **does not resolve publicly**
  (verified 2026-11-15: HTTPS fetch returns 404; `git ls-remote`
  fails). Do not vendor from it.
- Replacement candidate: **`https://github.com/lms-community/slimserver`**,
  tag **9.0.2** → commit `1470c941245ea3398ff9e4ef197ba275f9de8ba0`
  (peeled from tag object `7d636d1e34425304aaeffb3dc506273c3d26ba0`;
  tags 9.0.0–9.0.3 all present). Verified via `git ls-remote --tags`,
  2026-11-15. For reference, `github.com/Logitech/slimserver` HEAD
  resolves (`ec47a0ca…`) but is the dead upstream the WP1 survey
  already rejected.
- WP3 build plan (draft): fetch tag 9.0.2 to `/tmp`; identify the
  Radio/Music/Qobuz plugin set from the tree (plugin names TBD after
  fetch — none invented here); device side reuses `SlimBrowser` /
  `SlimMenus` already in the Jive tree (REQUIRED_SOURCES item 2).
  Server-side (LMS) vs device-side split decided at fetch time.
- Needs Lead approval to re-pin from `ralph-irving` to `lms-community`.

## 3. VPN: OpenVPN daemon (carried WP1 reference, not re-verified)

- `openvpn_2.5.11` tarball per the `meta-squeezeos` recipe
  (`https://swupdate.openvpn.org/community/releases/`), plus kernel
  `tun` from the WP2 kernel tree (Agent 1) — never the 2.6-era
  `tun.ko` blobs. Device-side applet/config remains WP3 work. The
  recipe URL was **not** re-fetched in WP2; verify at vendoring time.

## 4. No upstream yet (unchanged from WP1)

- `webui` (device-local web management UI): no sources; WP3 defines
  the server against `standalone/integration/web-routes.sh`.
- `proxy`: no source or requirement identified; stays UNIMPLEMENTED.
- `squeezeplay` backend command: owned by Agent 2; adapter ready.

## 5. What stays true until WP3

All 8 `backend.conf` files keep pointing at `unimplemented.sh`
(exit 3 + contract text). No `BACKEND_CMD` names a backend binary
until that backend's source is vendored and its real invocation is
known. See `docs/test-results/wp2-standalone.md` for the WP2
honesty checks.
