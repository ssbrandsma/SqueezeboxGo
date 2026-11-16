# UNINSTALL — SqueezeboxGo on StockOS (RG35XX H)

Removal is complete and reversible: SqueezeboxGo writes only to its own
three locations, so deleting them restores the pre-install state. Games,
saves, the frontend, and system configuration are never touched by
install or uninstall.

## Locations (the only three)

| # | Path | Backing |
|---|---|---|
| 1 | `Roms/APPS/SqueezeboxGo.sh`, `Roms/APPS/Imgs/SqueezeboxGo.png`, `Roms/APPS/SqueezeboxGo/` | VFAT card |
| 2 | `/opt/squeezebox-go/` (or `$HOME/squeezebox-go` if `/opt` was unwritable) | ext4 |
| 3 | `/dev/shm/squeezebox-go/` (or `/tmp/squeezebox-go/`) | RAM (vanishes on reboot) |

## Method A — from the handheld (no computer needed)

1. If SqueezeboxGo is running, leave it first (home menu →
   **Return to Anbernic**) so the frontend is back.
2. Over SSH (or a terminal), as root:
   ```sh
   rm -rf /opt/squeezebox-go ~/squeezebox-go \
          /dev/shm/squeezebox-go /tmp/squeezebox-go
   ```
   (Paths that don't exist are skipped; the command is idempotent.)
3. Delete the card files — either over the same shell
   (find the card's `APPS` dir first, e.g. `ls /mnt/*/APPS` — the mount
   point varies by slot):
   ```sh
   APPS=/mnt/<your-roms-mount>/APPS   # <-- adjust (see ls above)
   rm -f "$APPS/SqueezeboxGo.sh" "$APPS/Imgs/SqueezeboxGo.png"
   rm -rf "$APPS/SqueezeboxGo"
   ```
   …or power off, put the card in your computer, and delete
   `Roms/APPS/SqueezeboxGo.sh`, `Roms/APPS/Imgs/SqueezeboxGo.png`, and
   the `Roms/APPS/SqueezeboxGo/` folder.

## Method B — card only (no SSH)

1. Power off, put the card in your computer.
2. Delete the three card items listed above.
3. Put the card back and boot once: location 3 (RAM) is already gone;
   location 2 (ext4 runtime) becomes inert without its APPS entry —
   Jive can no longer start. (To also reclaim the ~60 MB on ext4, do
   Method A's step 2 over SSH, or leave it: it does nothing on its own.)

## Verify

- App Center no longer lists SqueezeboxGo.
- Stock UI, games, and saves behave exactly as before install.
- After a reboot, `ls /opt/squeezebox-go /dev/shm/squeezebox-go`
  shows nothing (when Method A was used).

## Reinstall

Follow [INSTALL](INSTALL.md) again — install after uninstall behaves
exactly like a first install.
