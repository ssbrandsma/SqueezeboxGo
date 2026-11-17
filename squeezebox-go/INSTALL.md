# INSTALL — SqueezeboxGo on StockOS (RG35XX H)

Installs native Squeezebox (Jive) as an App Center app. No reflash, no
system changes: files land only in `Roms/APPS/` (card) + one runtime
directory on ext4 (`/opt/squeezebox-go`). Games and saves are untouched.

Time: ~5 minutes. You need: the RG35XX H, its Roms card readable on your
computer (slot 01 or 02 — either works; App Center shows both), and the
release ZIP `SqueezeboxGo-<ver>-stockos-rg35xxh.zip`.

## 1. Copy the files

1. Download `SqueezeboxGo-<ver>-stockos-rg35xxh.zip` from the release.
2. Optional but recommended — verify the checksum (next to the ZIP):
   `sha256sum -c SqueezeboxGo-<ver>-stockos-rg35xxh.zip.sha256`.
3. Open the ZIP. Inside is one top-level folder, `APPS/`.
4. Copy the CONTENTS of the ZIP's `APPS/` folder into the card's
   `Roms/APPS/` folder (merge, don't replace), so the card ends up with:
   ```text
   Roms/APPS/SqueezeboxGo.sh
   Roms/APPS/Imgs/SqueezeboxGo.png
   Roms/APPS/SqueezeboxGo/VERSION
   Roms/APPS/SqueezeboxGo/SHA256SUMS
   Roms/APPS/SqueezeboxGo/payload.tar.gz
   ```
   Existing `APPS/Imgs/` content stays; only the SqueezeboxGo files are
   added. Eject the card properly before removing it.

## 2. Launch from App Center

1. Put the card back in the handheld and power on.
2. Open **App Center**, pick the TF slot holding the card if asked.
3. Select **SqueezeboxGo** (orange music-player icon).
4. First launch takes ~30–60 s: the entry script verifies the payload
   hash, installs the runtime to ext4, claims display/audio, and starts
   Jive. Later launches skip the install (idempotent).

## 3. Use it

- Jive's home menu works as usual (LMS/SlimProto playback, local UI).
- To leave: home menu → **Return to Anbernic**. Jive saves settings,
  stops playback, releases audio, restores mixer/display, and hands
  control back to the stock UI — no reboot.
- If anything looks wrong, the logs are on the device (RAM, fresh each
  boot): `/dev/shm/squeezebox-go/logs/` (`launch-*.log`, `jive.log`,
  `restore.log`), plus the persistent `/opt/squeezebox-go/install.log`.
  Rebooting always returns the device to the stock UI (nothing is
  disabled or masked).

## 4. Upgrade / reinstall

Repeat step 1 with the newer ZIP and launch again: the entry script
detects the version change and reinstalls the runtime automatically
(settings in `/opt/squeezebox-go/config/` survive). To force a clean
reinstall, follow [UNINSTALL](UNINSTALL.md) first.

## Display notes

- Only the **RG35XXH 640x480** skins work on this hardware (pre-selected).
  The Touch/Joggler/QVGA/WQVGA skins are for other devices: selecting one
  reprograms the video mode and garbles the screen. Your saved skin never
  changes, so quitting (Return to Anbernic) and relaunching always
  recovers to a clean display.
- First launch shows the App Center Loading screen for a while (~30–60 s
  on install, ~15 s after); 0.2.9+ unsticks itself automatically. If an
  older version sticks at Loading, reboot and upgrade.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| App Center shows no SqueezeboxGo | files in the wrong place (must be `Roms/APPS/…`, not `Roms/APPS/APPS/…`); wrong TF slot selected |
| Launch returns to App Center at once | install failed — read `/opt/squeezebox-go/install.log` over SSH; re-copy the ZIP (hash mismatch = bad copy) |
| No sound / "device busy" | another holder owns the PCM — the launch log names the frontend state; report it with the log |
| Black screen after Return | frontend restart failed — reboot (always safe); report with `/dev/shm/squeezebox-go/logs/launch-*.log` |
