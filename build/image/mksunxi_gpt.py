#!/usr/bin/env python3
"""mksunxi_gpt.py — deterministic sunxi-aware GPT writer for RG35XX H images.

Why this exists: the Allwinner BROM loads the SPL from raw offset 8 KiB
(sector 16). A stock GPT puts its 128-entry partition array at sectors 2-33,
so writing the SPL blob would corrupt the array (and vice versa). This writer
places the primary array at LBA 4096 (2 MiB) — past the SPL+U-Boot blob which
occupies sectors 16..~3000 — keeping the spec-compliant 128-entry count.
Partitions start at 16 MiB. All GUIDs are fixed (reproducible bytes).

Layout (see build/image/partitions.txt):
  LBA 0            protective MBR
  LBA 1            GPT header (primary)
  sectors 16..4095 RESERVED for SPL blob (@16) + U-Boot FIT (@512)
  LBA 4096..4127   GPT partition array (primary, 128 entries)
  p1 BOOT   16 MiB .. 272 MiB   FAT32, type EFI System
  p2 ROOTFS 272 MiB .. end-33s  ext4,  type Linux filesystem
  last 33 sectors  GPT array + header (backup)

Usage:
  mksunxi_gpt.py --image FILE --size-mb N [--disk-guid G --boot-partuuid B --root-partuuid R]
  mksunxi_gpt.py --image FILE --check
"""
import argparse
import struct
import sys
import uuid
import zlib

SECTOR = 512
ARRAY_LBA = 4096
N_ENTRIES = 128
ENTRY_SIZE = 128
ARRAY_SECTORS = N_ENTRIES * ENTRY_SIZE // SECTOR  # 32
BOOT_START = 16 * 1024 * 1024 // SECTOR          # 32768
BOOT_SIZE = 256 * 1024 * 1024 // SECTOR          # 524288
FIRST_USABLE = ARRAY_LBA + ARRAY_SECTORS         # 4128

TYPE_EFISYS = uuid.UUID("C12A7328-F81F-11D2-BA4B-00A0C93EC93B")
TYPE_LINUX = uuid.UUID("0FC63DAF-8483-4772-8E79-3D69D8477DE4")

DISK_GUID = uuid.UUID("0a1b2c3d-0000-4000-8000-000000000000")
BOOT_GUID = uuid.UUID("0a1b2c3d-0001-4000-8000-000000000000")
ROOT_GUID = uuid.UUID("0a1b2c3d-0002-4000-8000-000000000000")


def efi_guid_bytes(g: uuid.UUID) -> bytes:
    # Mixed-endian: first three fields little-endian, rest big-endian.
    return struct.pack("<IHH", g.time_low, g.time_mid, g.time_hi_version) + g.bytes[8:]


def guid_from_efi(b: bytes) -> uuid.UUID:
    a, c, d = struct.unpack("<IHH", b[:8])
    return uuid.UUID(bytes=struct.pack(">IHH", a, c, d) + b[8:])


def build_entry(type_g, uniq_g, start, end, name):
    raw = efi_guid_bytes(type_g) + efi_guid_bytes(uniq_g)
    raw += struct.pack("<QQQ", start, end, 0)
    raw += name.encode("utf-16-le")[:72].ljust(72, b"\0")
    assert len(raw) == ENTRY_SIZE
    return raw


def build_header(current, backup, first_us, last_us, disk_g, array_lba, array_crc):
    hdr = struct.pack(
        "<8sIIIIQQQQ16sQIII",
        b"EFI PART", 0x00010000, 92, 0, 0,
        current, backup, first_us, last_us,
        efi_guid_bytes(disk_g), array_lba, N_ENTRIES, ENTRY_SIZE, array_crc,
    )
    hdr = hdr.ljust(SECTOR, b"\0")
    crc = zlib.crc32(hdr[:92]) & 0xFFFFFFFF
    return hdr[:16] + struct.pack("<I", crc) + hdr[20:]


def protective_mbr(total_sectors):
    mbr = bytearray(SECTOR)
    size = min(total_sectors - 1, 0xFFFFFFFF)
    struct.pack_into("<B3sB3sII", mbr, 446, 0x00, b"\x00\x02\x00", 0xEE,
                     b"\xff\xff\xff", 1, size)
    mbr[510:512] = b"\x55\xaa"
    return bytes(mbr)


def write_image(path, size_mb, disk_guid, boot_guid, root_guid):
    total = size_mb * 1024 * 1024 // SECTOR
    if total < BOOT_START + BOOT_SIZE + 64:
        raise ValueError(f"image too small: {size_mb} MiB")
    last = total - 1
    last_us = total - 1 - ARRAY_SECTORS
    boot_start, boot_end = BOOT_START, BOOT_START + BOOT_SIZE - 1
    root_start, root_end = BOOT_START + BOOT_SIZE, last_us

    array = bytearray(N_ENTRIES * ENTRY_SIZE)
    array[0:128] = build_entry(TYPE_EFISYS, boot_guid, boot_start, boot_end, "BOOT")
    array[128:256] = build_entry(TYPE_LINUX, root_guid, root_start, root_end, "ROOTFS")
    array_crc = zlib.crc32(bytes(array)) & 0xFFFFFFFF

    primary = build_header(1, last, FIRST_USABLE, last_us, disk_guid, ARRAY_LBA, array_crc)
    backup = build_header(last, 1, FIRST_USABLE, last_us, disk_guid, last - ARRAY_SECTORS, array_crc)

    with open(path, "r+b") as f:
        f.seek(0)
        f.write(protective_mbr(total))
        f.seek(SECTOR)
        f.write(primary)
        f.seek(ARRAY_LBA * SECTOR)
        f.write(array)
        f.seek((last - ARRAY_SECTORS) * SECTOR)
        f.write(array)
        f.seek(last * SECTOR)
        f.write(backup)
    return {"sectors": total, "boot": (boot_start, boot_end), "root": (root_start, root_end)}


def parse_header(buf, expect_current):
    sig, rev, hsize, crc, rsv, cur, bak, fus, lus = struct.unpack("<8sIIIIQQQQ", buf[:56])
    if sig != b"EFI PART":
        raise ValueError("bad GPT signature")
    if (zlib.crc32(buf[:16] + b"\0\0\0\0" + buf[20:hsize]) & 0xFFFFFFFF) != crc:
        raise ValueError("GPT header CRC mismatch")
    if cur != expect_current:
        raise ValueError(f"header LBA field {cur} != position {expect_current}")
    dg = guid_from_efi(buf[56:72])
    arr_lba, nent, esz, arr_crc = struct.unpack("<QIII", buf[72:92])
    return {"backup": bak, "first_usable": fus, "last_usable": lus, "disk_guid": dg,
            "array_lba": arr_lba, "n_entries": nent, "entry_size": esz, "array_crc": arr_crc}


def check_image(path):
    with open(path, "rb") as f:
        mbr = f.read(SECTOR)
        if mbr[510:512] != b"\x55\xaa" or mbr[450] != 0xEE:
            raise ValueError("protective MBR missing/invalid")
        f.seek(0, 2)
        total = f.tell() // SECTOR
        f.seek(SECTOR)
        prim = parse_header(f.read(SECTOR), 1)
        f.seek(prim["array_lba"] * SECTOR)
        arr = f.read(prim["n_entries"] * prim["entry_size"])
        if (zlib.crc32(arr) & 0xFFFFFFFF) != prim["array_crc"]:
            raise ValueError("primary array CRC mismatch")
        f.seek((total - 1) * SECTOR)
        bak = parse_header(f.read(SECTOR), total - 1)
        if bak["backup"] != 1:
            raise ValueError("backup header back-pointer broken")
        parts = []
        for i in range(prim["n_entries"]):
            e = arr[i * 128:(i + 1) * 128]
            if e[:16] == b"\0" * 16:
                continue
            tg, ug = guid_from_efi(e[:16]), guid_from_efi(e[16:32])
            s, en, _ = struct.unpack("<QQQ", e[32:56])
            name = e[56:128].decode("utf-16-le").rstrip("\0")
            parts.append((i + 1, str(tg), str(ug), s, en, name))
    return {"sectors": total, "disk_guid": str(prim["disk_guid"]), "parts": parts}


def main(argv=None):
    ap = argparse.ArgumentParser(description="sunxi-aware deterministic GPT writer")
    ap.add_argument("--image", required=True)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--size-mb", type=int, default=2048)
    ap.add_argument("--disk-guid", default=str(DISK_GUID))
    ap.add_argument("--boot-partuuid", default=str(BOOT_GUID))
    ap.add_argument("--root-partuuid", default=str(ROOT_GUID))
    a = ap.parse_args(argv)
    if a.check:
        info = check_image(a.image)
        print(f"GPT OK: {info['sectors']} sectors, disk {info['disk_guid']}")
        for n, tg, ug, s, en, name in info["parts"]:
            print(f"p{n}: {name} sectors {s}..{en} partuuid={ug} type={tg}")
        return 0
    with open(a.image, "wb") as f:
        f.truncate(a.size_mb * 1024 * 1024)
    info = write_image(a.image, a.size_mb, uuid.UUID(a.disk_guid),
                       uuid.UUID(a.boot_partuuid), uuid.UUID(a.root_partuuid))
    print(f"wrote {a.image}: {info['sectors']} sectors "
          f"boot={info['boot'][0]}..{info['boot'][1]} root={info['root'][0]}..{info['root'][1]}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as ex:
        print(f"mksunxi_gpt.py: ERROR: {ex}", file=sys.stderr)
        sys.exit(1)
