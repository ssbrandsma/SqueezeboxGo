# GO evtest + human-gate checklist — PREPARED, not run (no human fingers this session)

## evtest capture (reuses existing handoff)
The full capture procedure already exists: [evtest-handoff.md](evtest-handoff.md)
(device nodes, per-button code table, power-key query-only rule). GO adds no new
evtest need — the SqueezeboxGo input path uses the same event1/event2 nodes and
the `evdev2jive.map` the capture validates. When fingers are available, run that
handoff as written, then the GO items below.

## GO human-gated checks (queue for owner; PRECONDITION noted)
PRECONDITION for items 2-4: GO-APP's Return-to-Anbernic Jive action
(`SQUEEZEBOX_GO=1` gate). Without it a menu-launched Jive cannot be exited from
the device itself (power key only suspends); the SSH fallback is
`sudo -n kill -TERM $(pidof jive)` + `sudo -n systemctl start launcher.service`.

1. App Center icon/menu visibility (runnable NOW, no precondition):
   Open APPS on the device; confirm a `SqueezeboxGo` entry with a dark-blue
   provisional icon exists alongside the 6 stock apps. Report: visible? icon
   renders? (provisional art — GO-APP final art replaces it).
2. Menu launch + Jive boot on LCD (needs precondition for safe exit):
   Launch SqueezeboxGo from App Center; report what the LCD shows (expect the
   Jive UI at 640x480; fb writes were proven but on-LCD visibility is human-only).
3. Button nav + audio ears: Dpad/A/B navigate Jive; play any source; report
   controls and sound (note: `decode_alsa_init shmget` SYSVIPC error is logged —
   if audio is silent/broken, that is suspect #1 for the audio agent).
4. Exit path from menu: trigger Return to Anbernic; report frontend return
   WITHOUT reboot (SSH path already proved this; menu path needs fingers).
5. Game launchable after exit: launch any game + confirm saves intact
   (GO install is additive-only; nothing under /mnt/vendor, /mnt/mod, or TF2
   was modified — this check confirms no collateral).

## Exact fallback commands (SSH, for the agent on duty)
```sh
# replicate menu-run state (dmenu MUST be dead first — it holds the PCM):
sudo -n systemctl stop launcher.service
for i in $(seq 1 12); do p=$(pidof dmenu.bin); [ -z "$p" ] && break; sleep 5; done
pidof dmenu.bin || echo DMENU_GONE
# run exactly what the menu runs:
/mnt/mmc/Roms/APPS/SqueezeboxGo.sh &   # as root over SSH, or sudo -n
tail -f /opt/squeezebox-go/logs/jive.log
# exit + frontend return:
sudo -n kill -TERM $(pidof jive)
sudo -n systemctl start launcher.service   # dmenu self-heals vinfo to 1280x1024x16
pidof dmenu.bin && sudo -n fuser /dev/snd/pcmC0D0p
```
