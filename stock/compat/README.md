# stock/compat — StockOS compatibility shims (source + rationale)

## sysv_shim.so (from sysv_shim.c)

The Anbernic stock kernel (4.9.170) has no SysV IPC (`SYSVIPC=n`):
`shmget`/`semget` fail with `ENOSYS`. SqueezePlay's `decode_alsa`
shares its audio ring buffer between `jive` and the forked `jive_alsa`
helper via one SysV segment (key 56833); without it `decode_alsa_init`
fails and Jive has no audio at all (proven live 2026-11-16).

The shim implements the used subset (`shmget`/`shmat`/`shmdt`/
`shmctl IPC_RMID`) over POSIX `shm_open`/`mmap`, loaded via
`LD_PRELOAD` (inherited by the exec'd helper, so both ends agree).

### Binary provenance (explicitly justified)

`sysv_shim.so` (12968 bytes, md5 `a3e88487ea82e30360d928b6f3a92bb9`)
is committed because the release packer runs on an x86_64 host with no
aarch64 toolchain, while the app cannot produce audio without it.
Built natively on the RG35XX H (glibc 2.35, max symbol `GLIBC_2.34`):

```sh
gcc -shared -fPIC -O2 -o sysv_shim.so sysv_shim.c
```

from `sysv_shim.c` at commit `824e65e`. Rebuild any time on the
device with the same one-liner; replace with a cross-built copy once
the host toolchain exists (then delete this binary and note it here).

## evdev2jive-stock (from ui/input/evdev2jive.c)

evdev → uinput keyboard mapper (`rg35xxh-jive-keys` node). Jive reads
physical buttons through it; without it controls are dead (proven
live 2026-11-16: Go 0.2.1 booted with no mapper, no input).
Same binary-in-git justification as the shim (tiny, device-built,
app-critical). Built on the RG35XX H:

```sh
gcc -std=c99 -Wall -Wextra -O2 -o evdev2jive-stock ui/input/evdev2jive.c
```

Smoke-proven on device (grabs ANBERNIC-keys, creates the uinput
node). Map file lives next to it in the payload (`input/`).
