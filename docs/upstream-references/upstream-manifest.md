# Upstream manifest (pinned)

| Component | Repo | Pin | Role |
|---|---|---|---|
| squeezeplay | github.com/ralph-irving/squeezeplay | `758bc11` (2026-09-25) | UI+playback base |
| squeezeos-squeezeplay | github.com/ralph-irving/squeezeos-squeezeplay | `766b6a8` | backports only |
| squeezelite | github.com/ralph-irving/squeezelite | `cc7ee7c` (2026-10-28) | audio/SlimProto ref |
| jivelite | github.com/ralph-irving/jivelite | `d43a20b` | aarch64 recipe |
| tcz-jivelite | github.com/ralph-irving/tcz-jivelite | `4bdf677` | aarch64 patches |
| EDO | github.com/ralph-irving/squeezeplay-EnhancedDigitalOutput | TBD (WP2 vendor) | USB-DAC/hi-res |
| sdl12-compat | github.com/libsdl-org/sdl12-compat | `release-1.2.78` (`07043bdc`) | SDL1.2-on-SDL2 |
| linux (stable) | git.kernel.org stable/linux.git | `v7.3.4` (`8310b43a`) | kernel + H700 DTS |
| u-boot | github.com/u-boot/u-boot | `v2026.10` (`55084065`) | `anbernic_rg35xx_h700_defconfig` |
| ATF | github.com/ARM-software/arm-trusted-firmware | `v2.15.0` (`da738d5e`) | BL31 sun50i_h616 |
| image container | debian:bookworm-slim | `sha256:734a72b3…b179bc` | image build env |
| slimserver | github.com/lms-community/slimserver | `9.0.2` peeled `1470c941` | standalone ref (Lead re-pin: ralph-irving 404 verified) |
| librespot | github.com/librespot-org/librespot | `v0.8.0` (`d36f9f19`) | Spotify Connect backend |

Update pins only with Lead approval; record date + reason.
