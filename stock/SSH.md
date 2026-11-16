# Wi-Fi + SSH from the UART shell (stock Jammy)

Goal: reach the stock system over SSH so probe tarballs and bundles
move via `scp` instead of UART paste. All commands run **on the device
as root** over UART (115200 8N1, `ttyS0`) unless marked `host:`.
Wi-Fi credentials are the ONE sanctioned persistent change in track
B3 — every step below ships its exact undo.

## 0. See what the stock image uses (30 seconds, read-only)

```sh
ip link                          # radio present? (expect wlan0, module 8821cs)
nmcli dev status                 # if this works, NetworkManager owns Wi-Fi
ls /etc/netplan/                 # if *.yaml exists, netplan is in play
systemctl is-active NetworkManager systemd-networkd ssh
```

- `nmcli` works → **Path A** (most likely on a gaming image with a
  Wi-Fi UI; the stock UI already manages connections this way).
- Only netplan + `systemd-networkd` → **Path B**.
- Both present: NetworkManager wins for Wi-Fi on stock Ubuntu unless
  a netplan YAML explicitly hands `wlan0` to networkd — check the
  YAML renderer before touching anything.

`60-network.txt` in the probe tarball already captured all of this;
use it instead of re-typing if you probed first.

## Path A — NetworkManager (`nmcli`)

```sh
nmcli dev wifi rescan
nmcli dev wifi list               # 2.4 GHz SSIDs (8821cs is 2.4/5 capable; try 2.4 first)
# --ask reads the PSK without putting it in history or `ps` output:
nmcli dev wifi connect '<SSID>' --ask
ip addr show wlan0                # note the IP for ssh/scp
ping -c3 <gateway-ip>
```

Undo (forgets the network entirely):

```sh
nmcli con delete '<SSID>'
```

## Path B — netplan + systemd-networkd

Only if Path A does not apply. This writes ONE file; back it up first
so the undo is exact.

```sh
ls /etc/netplan/
cp -a /etc/netplan/01-stock.yaml /etc/netplan/01-stock.yaml.bak  # adjust name to reality
cat > /etc/netplan/60-wifi.yaml <<'EOF'
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "<SSID>":
          password: "<PSK>"
EOF
chmod 600 /etc/netplan/60-wifi.yaml
netplan apply
ip addr show wlan0
```

Undo:

```sh
rm /etc/netplan/60-wifi.yaml
mv /etc/netplan/01-stock.yaml.bak /etc/netplan/01-stock.yaml  # only if you made one
netplan apply
```

Never commit a YAML containing a PSK, and never paste one into a
results file — the probe redacts these automatically.

## SSH server

```sh
systemctl is-active ssh || systemctl status ssh --no-pager
ss -tlnp | grep ':22'             # listening?
```

- If `ssh.service` is missing entirely: `apt update && apt install -y
  openssh-server` is a system change — your call, with the usual
  reversibility caveat (`apt purge openssh-server` undoes it, but it
  is outside the track's no-system-writes rule, so record it if you
  do it). Stock gaming images almost always ship it already.
- Jammy uses `ssh.service` (alias `sshd.service` also resolves).
  Do NOT enable/disable anything — if it is running, leave it; if it
  is socket-activated, leave that too.

## Key install (from the UART shell)

Typing a full key over UART is painful; paste it in ONE `printf` (UART
paste is slow — give it a few seconds, do not hammer Enter):

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf '%s\n' 'ssh-ed25519 AAAA...your-public-key... comment' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
cat ~/.ssh/authorized_keys       # verify: exactly one line per key, no wraps
```

Then from the host:

```sh
host: ssh -o PasswordAuthentication=no root@<device-ip> 'uname -a'
host: scp stock/probe/stock-probe.sh 'root@<device-ip>:~/'
host: scp 'root@<device-ip>:~/stock-probe-*.tar.gz*' .
```

If the stock image disables root SSH login
(`PermitRootLogin` in `/etc/ssh/sshd_config` — read, do not edit
yet): log in as the stock user instead (`ls /home`, `getent passwd`
show candidates; `00-meta.txt` lists them). Copying the bundle to
`$HOME/squeezebox-stock` works fine as non-root; only the
`systemctl stop/start` steps need root (`sudo`/`su`).

## Gotchas

- **UART paste**: keep pastes under ~2 KB per chunk; `printf '%s\n'`
  beats heredocs over a slow line. Verify with `cat`, then `sha256sum`
  the transferred script against the host copy.
- **2.4 GHz first**: the `8821cs` vendor module is happier there;
  some 5 GHz / WPA3 / mesh setups associate but never DHCP.
- **Power save**: if SSH stalls after idle,
  `iw dev wlan0 set power_save off` (runtime only, reboot clears it).
- **Wrong interface name**: `ip link` is truth — use whatever it
  shows (`wlan0`, `wlp1s0`, …), not what this doc guesses.
- **Firewall**: `ufw status` — if active and port 22 is closed,
  that is a stock-image firewall decision; record it, do not punch
  holes silently.
- **Host keys**: first `ssh` prompts to trust the device key —
  verify the fingerprint over UART (`ssh-keygen -lf
  /etc/ssh/ssh_host_ed25519_key.pub`) before typing `yes`.
- **Never** put the PSK in a results file, a commit, or a shared
  chat log. Redact first; the probe already does.
