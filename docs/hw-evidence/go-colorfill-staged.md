# go-colorfill STAGED (prepared, NOT run — live session only)
# Agent: HW go-redeploy, 2026-11-16. Task 5: verify + stage, do not run.

## Verified (all reversible, no fb writes, dmenu alive throughout)

```text
$ scp stock/bundle/color-fill.py rg35xxh:/tmp/color-fill.py
scp_rc=0
$ python3 -m py_compile /tmp/color-fill.py && echo COMPILE_OK
COMPILE_OK
$ python3 /tmp/color-fill.py --badarg; echo "usage_rc=$?"
usage: sudo python3 color-fill.py [--hold SECONDS]
usage_rc=2
$ sudo -n python3 -c "open(\"/dev/fb0\",\"r+b\").close(); print(\"FB0_RW_OK\")"
FB0_RW_OK
$ sha256sum /tmp/color-fill.py
666befe1d8c3fb8ef2c3dcce473173f7922db4909da731c1d27d94ff1b26507e  /tmp/color-fill.py
```

- Script on device at /tmp/color-fill.py (sha above — matches repo
  file at commit 3ba37ff; re-verify with `sha256sum` on the day,
  /tmp may have been cleared by a reboot).
- sudo works (`sudo -n` non-interactive, verified all session).
- fb0 writable as root (open r+b OK; full PUT cycle proven 3x with
  vinfo-full.py this session).
- Color-fill geometry path (FBIOGET live query, 16→RGB565 /
  32→XRGB8888, 5 MB sanity cap) matches the observed vinfo range.

## Staged one-command live session (TWO people/shells + owner GO)

Preconditions: device awake, dmenu alive (stock side), watcher on LCD.
Operator (SSH):

```sh
sudo -n rm -f /tmp/.next   # double-run race guard (go-redeploy finding)
sudo -n systemctl stop launcher.service
for i in $(seq 1 12); do p=$(pidof dmenu.bin); [ -z "$p" ] && break; sleep 5; done
pidof dmenu.bin || echo DMENU_GONE
sudo -n python3 /tmp/color-fill.py --hold 4
```

Watcher reports after EACH color (RED/GREEN/BLUE ~4 s): full-screen?
partial? unchanged? exact coverage. Script ends BLACK + restarts the
frontend itself; operator verifies:

```sh
systemctl is-active launcher.service; pidof dmenu.bin
python3 /tmp/vinfo-full.py get 2>/dev/null | grep -E "xres |yres |bpp " \
  || python3 -c "import fcntl,struct;f=open('/dev/fb0','rb');v=fcntl.ioctl(f,0x4600,b'\x00'*160);print(struct.unpack('III',v[0:12]))"
```

Expected outcomes (unchanged from the script header): full R/G/B =
fb0 reaches the panel (DE routes fb0); unchanged = disp-direct layer
(no fbcon video claim); partial/offset = geometry mismatch (record
exact appearance). If vinfo is stuck afterwards: `sudo -n python3
/tmp/vinfo-full.py put-stock` (+ restart frontend) — proven 3x.
If /tmp was wiped (reboot): re-scp color-fill.py + vinfo-full.py
from the hw/go-redeploy branch first.
