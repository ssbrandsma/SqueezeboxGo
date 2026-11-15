# Upstream manifest (pinned)

| Component | Repo | Pin | Role |
|---|---|---|---|
| squeezeplay | github.com/ralph-irving/squeezeplay | `758bc11` (2026-09-25) | UI+playback base |
| squeezeos-squeezeplay | github.com/ralph-irving/squeezeos-squeezeplay | `766b6a8` | backports only |
| squeezelite | github.com/ralph-irving/squeezelite | `cc7ee7c` (2026-10-28) | audio/SlimProto ref |
| jivelite | github.com/ralph-irving/jivelite | `d43a20b` | aarch64 recipe |
| tcz-jivelite | github.com/ralph-irving/tcz-jivelite | `4bdf677` | aarch64 patches |
| EDO | github.com/ralph-irving/squeezeplay-EnhancedDigitalOutput | TBD (WP1 vendor) | USB-DAC/hi-res |
| sdl12-compat | github.com/libsdl-org/sdl12-compat | TBD (WP1 vendor) | SDL1.2-on-SDL2 |
| linux | torvalds/linux (+ROCKNIX-class OOT) | TBD (WP1, ≈7.1.x) | kernel + H700 DTS |
| u-boot | u-boot master | TBD (WP1) | `anbernic_rg35xx_h700_defconfig` |

Update pins only with Lead approval; record date + reason.
