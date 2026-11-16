# stock-probe.sh — read-only device collector

Single-file, dependency-free collector. Runs **on the device as root**
(UART shell), writes one tarball in the current directory, changes
nothing else.

## Exact run (on device)

```sh
# As root over UART (115200 8N1, ttyS0). Get the script onto the device
# by any read-only-friendly means: paste via UART, scp it over (see
# ../SSH.md once networking is up), or copy from a USB stick.
sh stock-probe.sh
# -> ./stock-probe-<UTC-timestamp>-<host>.tar.gz (+ .sha256)

# Copy back to your host (from the host side):
scp 'root@<device-ip>:~/stock-probe-*.tar.gz*' .
sha256sum -c stock-probe-*.tar.gz.sha256
tar -xzf stock-probe-*.tar.gz
```

Root is required for the good stuff (`dmesg`, `fuser`, full
`systemctl`); as a normal user the script still runs but those blocks
say so. No `apt install` needed: every probed tool is used only if
present, and absence is recorded instead of failing.

## What lands in the tarball

| File | Contents (all read-only sources) |
|---|---|
| `00-meta.txt` | kernel version, os-release, cmdline, uptime, users |
| `10-framebuffer.txt` | `fbset -s/-i`, `/proc/fb`, fb0 sysfs attrs, `/dev/dri` check |
| `20-sdl.txt` | ldconfig SDL entries, SDL lib files, sdl-config, `SDL_*` env |
| `30-alsa.txt` | `aplay -l/-L`, `amixer scontrols` (all cards), `/proc/asound/*`, `fuser -v /dev/snd/*` PCM-holder check |
| `40-input.txt` | `/dev/input/by-id`, `by-path`, event nodes, `/proc/bus/input/devices` |
| `50-processes-services.txt` | `ps auxf`, all/running/failed units, unit files, default target, `lsmod` |
| `60-network.txt` | `ip link/addr/route`, listeners, nmcli, netplan (PSK-redacted), ssh state |
| `70-storage-mounts.txt` | mounts, partitions, `lsblk`, `df -h` |
| `80-packages.txt` | SDL/ALSA/display/frontend `dpkg -l` grep + full `dpkg -l` |
| `90-frontend-hunt.txt` | frontend process/unit identification bundle |
| `99-env-dmesg.txt` | env, dmesg display/audio/input excerpts, journal errors |

Privacy notes: netplan PSKs/passwords are redacted in-line;
NetworkManager profile *contents* are never collected (filenames
only). Skim `99-env-dmesg.txt` for secrets before attaching the
tarball anywhere public.
