#!/usr/bin/env python3
"""SD image validation gate (WP2 QA).

Validates an assembled RG35XX H image (`.img` file) or a mounted/staging
tree (directory) against the WP1/WP2 layout contract:

  * GPT layout: protective MBR, sunxi-aware primary header (LBA 1) + array
    at LBA 4096, backup header; partition start/size/type checks against
    build/image/partitions.txt + mksunxi_gpt.py constants.
  * SPL blob present at raw sector 16 (non-zero), array CRC intact.
  * Boot files present: BOOT.SCR, IMAGE, DTB.IMG in the FAT32 boot
    partition root (pure-python FAT32 directory scan, no mount needed).
  * DTB present (dtb.img / *.dtb); rootfs markers (etc/) for trees.
  * No-secrets scan over raw image bytes / tree files.
  * Size limits (--min-mb / --max-mb).

Targets: positional paths (`.img` files or directories). With no args the
gate searches build/out/*.img and $IMAGE_UNDER_TEST; when nothing is
found it reports NOT RUN (honest non-result, exit 3).

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN, 4 BLOCKED. See tests/qa_lib.py.
"""

import argparse
import os
import re
import struct
import sys
import uuid
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import (repo_root, emit, PASS, FAIL, NOTRUN, BLOCKED)

SECTOR = 512
ARRAY_LBA = 4096
N_ENTRIES = 128
ENTRY_SIZE = 128
BOOT_START = 32768          # 16 MiB
BOOT_SECTORS = 524288       # 256 MiB
ROOT_START = 557056          # 272 MiB

TYPE_EFISYS = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
TYPE_LINUX = "0fc63daf-8483-4772-8e79-3d69d8477de4"
BOOT_PARTUUID = "0a1b2c3d-0001-4000-8000-000000000000"
ROOT_PARTUUID = "0a1b2c3d-0002-4000-8000-000000000000"

BOOT_FILES = ["BOOT.SCR", "IMAGE", "DTB.IMG"]  # 8.3 names in FAT root

SECRET_PATTERNS = [
    (re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
     "PEM private key header"),
    (re.compile(rb"AKIA[0-9A-Z]{16}"), "AWS access-key id"),
    (re.compile(rb"ghp_[A-Za-z0-9]{20,}"), "GitHub token"),
    (re.compile(rb"xox[baprs]-[A-Za-z0-9-]{10,}"), "Slack token"),
    (re.compile(rb"aws_secret_access_key.{0,20}[A-Za-z0-9/+=]{20,}"),
     "AWS secret key"),
]


def guid_from_efi(b):
    a, c, d = struct.unpack("<IHH", b[:8])
    return str(uuid.UUID(bytes=struct.pack(">IHH", a, c, d) + b[8:]))


def check_gpt(path, details, problems, relaxed_uuids):
    """Parse and validate GPT bytes. Returns (boot_start, boot_sectors)."""
    size = os.path.getsize(path)
    total = size // SECTOR
    with open(path, "rb") as f:
        mbr = f.read(SECTOR)
        if len(mbr) < SECTOR or mbr[510:512] != b"\x55\xaa":
            problems.append("protective MBR boot signature 55 AA missing")
        elif mbr[450] != 0xEE:
            problems.append(f"MBR partition type {mbr[450]:#x}, want 0xEE")
        else:
            details.append("protective MBR ok (0xEE, boot sig)")

        f.seek(SECTOR)
        hdr = f.read(SECTOR)
        if hdr[:8] != b"EFI PART":
            problems.append("GPT primary header signature missing at LBA 1")
            return None
        hsize = struct.unpack("<I", hdr[12:16])[0]
        want_crc = struct.unpack("<I", hdr[16:20])[0]
        got_crc = zlib.crc32(hdr[:16] + b"\0\0\0\0" + hdr[20:hsize]) & 0xFFFFFFFF
        if got_crc != want_crc:
            problems.append("GPT primary header CRC mismatch")
        else:
            details.append("GPT primary header CRC ok")
        cur, bak = struct.unpack("<QQ", hdr[24:40])
        if cur != 1:
            problems.append(f"primary header LBA field {cur} != 1")
        if bak != total - 1:
            problems.append(f"backup LBA pointer {bak} != last sector "
                            f"{total - 1}")
        arr_lba, nent, esz, arr_crc = struct.unpack("<QIII", hdr[72:92])
        if arr_lba != ARRAY_LBA:
            problems.append(f"GPT array at LBA {arr_lba}, want sunxi "
                            f"{ARRAY_LBA}")
        else:
            details.append(f"GPT array at sunxi LBA {ARRAY_LBA} ok")
        if (nent, esz) != (N_ENTRIES, ENTRY_SIZE):
            problems.append(f"array {nent}x{esz}, want "
                            f"{N_ENTRIES}x{ENTRY_SIZE}")
        f.seek(arr_lba * SECTOR)
        arr = f.read(nent * esz)
        if (zlib.crc32(arr) & 0xFFFFFFFF) != arr_crc:
            problems.append("GPT primary array CRC mismatch")
        else:
            details.append("GPT primary array CRC ok")

        parts = []
        for i in range(nent):
            e = arr[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE]
            if e[:16] == b"\0" * 16:
                continue
            tg = guid_from_efi(e[:16])
            ug = guid_from_efi(e[16:32])
            s, en, _ = struct.unpack("<QQQ", e[32:56])
            name = e[56:128].decode("utf-16-le", "replace").rstrip("\0")
            parts.append({"n": i + 1, "type": tg, "uuid": ug,
                          "start": s, "end": en, "name": name})
        want = [
            {"n": 1, "name": "BOOT", "type": TYPE_EFISYS,
             "uuid": BOOT_PARTUUID, "start": BOOT_START,
             "end": BOOT_START + BOOT_SECTORS - 1},
            {"n": 2, "name": "ROOTFS", "type": TYPE_LINUX,
             "uuid": ROOT_PARTUUID, "start": ROOT_START,
             "end": total - 1 - 32},
        ]
        boot_span = None
        for w in want:
            got = next((p for p in parts if p["n"] == w["n"]), None)
            if got is None:
                problems.append(f"p{w['n']} {w['name']}: entry missing")
                continue
            errs = []
            if got["type"] != w["type"]:
                errs.append(f"type {got['type']}")
            if got["uuid"] != w["uuid"] and not relaxed_uuids:
                errs.append(f"partuuid {got['uuid']}")
            if (got["start"], got["end"]) != (w["start"], w["end"]):
                errs.append(f"span {got['start']}..{got['end']}")
            if errs:
                problems.append(f"p{w['n']} {w['name']}: " + "; ".join(errs) +
                                f" (want type={w['type']} uuid={w['uuid']} "
                                f"span={w['start']}..{w['end']})")
            else:
                details.append(f"p{w['n']} {w['name']}: "
                               f"{got['start']}..{got['end']} ok")
            if w["n"] == 1 and not errs:
                boot_span = (got["start"], got["end"] - got["start"] + 1)

        # Backup header.
        f.seek((total - 1) * SECTOR)
        bhdr = f.read(SECTOR)
        if bhdr[:8] != b"EFI PART":
            problems.append("GPT backup header signature missing")
        else:
            bhsize = struct.unpack("<I", bhdr[12:16])[0]
            bwant = struct.unpack("<I", bhdr[16:20])[0]
            bgot = zlib.crc32(bhdr[:16] + b"\0\0\0\0"
                              + bhdr[20:bhsize]) & 0xFFFFFFFF
            if bgot != bwant:
                problems.append("GPT backup header CRC mismatch")
            else:
                details.append("GPT backup header ok")

        # SPL blob at sector 16 (BROM load address): must be non-empty.
        f.seek(16 * SECTOR)
        spl_head = f.read(4096)
        if spl_head.strip(b"\0") == b"":
            problems.append("SPL blob missing at sector 16 (all zero)")
        else:
            details.append("SPL blob present at sector 16")
    return boot_span


def fat_root_names(path, part_start):
    """Return short-name directory entries of a FAT32 root dir.

    Raises ValueError when the partition is not parseable FAT.
    """
    with open(path, "rb") as f:
        f.seek(part_start * SECTOR)
        bpb = f.read(SECTOR)
    if bpb[510:512] != b"\x55\xaa":
        raise ValueError("boot partition has no FAT boot signature")
    bps, spc = struct.unpack("<HB", bpb[11:14])
    rsvd, nfats = struct.unpack("<HH", bpb[14:18])
    fatsz = struct.unpack("<I", bpb[36:40])[0]
    root_clus = struct.unpack("<I", bpb[44:48])[0]
    if bps != 512 or spc == 0 or rsvd == 0 or nfats == 0 or fatsz == 0:
        raise ValueError("boot partition BPB is not valid FAT32")
    if bpb[82:87] not in (b"FAT32", b"FAT16"):
        raise ValueError("boot partition is not FAT "
                         f"(type tag {bpb[82:87]!r})")
    data_lba = part_start + rsvd + nfats * fatsz
    names = []
    with open(path, "rb") as f:
        # Root dir chain: follow at most 16 clusters from root_clus via FAT.
        f.seek((part_start + rsvd) * SECTOR)
        fat = f.read(min(fatsz * SECTOR, 1 << 20))
        clus, seen = root_clus, 0
        while clus < 0x0FFFFFF8 and seen < 16:
            seen += 1
            f.seek((data_lba + (clus - 2) * spc) * SECTOR)
            chunk = f.read(spc * SECTOR)
            for off in range(0, len(chunk), 32):
                ent = chunk[off:off + 32]
                if ent[0] == 0x00:
                    return names
                if ent[0] == 0xE5 or ent[11] == 0x0F:
                    continue  # deleted / LFN
                raw = ent[0:11].decode("ascii", "replace")
                name = (raw[0:8].rstrip() + "." + raw[8:11].rstrip()
                        if raw[8:11].strip() else raw[0:8].rstrip())
                names.append(name.upper())
            nxt = struct.unpack("<I", fat[clus * 4:clus * 4 + 4])[0] & 0x0FFFFFFF
            if nxt < 2 or nxt == clus:
                break
            clus = nxt
    return names


def scan_bytes_for_secrets(data, origin, details, problems):
    for rx, label in SECRET_PATTERNS:
        if rx.search(data):
            problems.append(f"{origin}: possible secret ({label})")


def scan_image_secrets(path, details, problems):
    overlap = 256
    carry = b""
    try:
        with open(path, "rb") as f:
            while True:
                chunk = f.read(1 << 20)
                if not chunk:
                    break
                scan_bytes_for_secrets(carry + chunk,
                                       os.path.basename(path),
                                       details, problems)
                carry = chunk[-overlap:]
    except OSError as e:
        problems.append(f"secret scan failed on {path}: {e}")
        return
    if not any("possible secret" in p for p in problems):
        details.append("no-secrets scan clean")


def check_image_file(path, details, problems, args):
    rel = os.path.relpath(path, args.root)
    size = os.path.getsize(path)
    size_mb = size / (1024 * 1024)
    details.append(f"{rel}: {size} bytes ({size_mb:.1f} MiB)")
    if size_mb < args.min_mb:
        problems.append(f"{rel}: image {size_mb:.1f} MiB < min "
                        f"{args.min_mb} MiB")
    if size_mb > args.max_mb:
        problems.append(f"{rel}: image {size_mb:.1f} MiB > max "
                        f"{args.max_mb} MiB")
    if size % SECTOR != 0:
        problems.append(f"{rel}: size not a multiple of 512")
    span = check_gpt(path, details, problems,
                     relaxed_uuids=args.relaxed_uuids)
    if span and not args.skip_bootfs:
        try:
            names = fat_root_names(path, span[0])
        except ValueError as e:
            problems.append(f"{rel}: boot files unreadable: {e}")
        else:
            for want in BOOT_FILES:
                if want in names:
                    details.append(f"{rel}: boot file present: {want}")
                else:
                    problems.append(f"{rel}: boot file missing: {want} "
                                    f"(FAT root has: "
                                    f"{', '.join(sorted(names)[:12]) or 'none'})")
    elif span and args.skip_bootfs:
        details.append("boot-fs listing skipped (--skip-bootfs)")
    scan_image_secrets(path, details, problems)


TEXT_EXT_OK = {"", ".txt", ".md", ".cmd", ".conf", ".cfg", ".json",
               ".sh", ".py", ".map", ".lst", ".dts", ".dtsi", ".env"}


def check_tree(path, details, problems, args):
    rel = os.path.relpath(path, args.root)
    total = 0
    nfiles = 0
    secret_hits = 0
    boot_hits = {}
    for dirpath, dirnames, filenames in os.walk(path):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            full = os.path.join(dirpath, name)
            try:
                st = os.path.getsize(full)
            except OSError:
                continue
            total += st
            nfiles += 1
            up = name.upper()
            if up in ("BOOT.SCR", "IMAGE", "DTB.IMG") or \
                    name.endswith(".dtb"):
                boot_hits[up if up in ("BOOT.SCR", "IMAGE", "DTB.IMG")
                          else "DTB.IMG"] = os.path.relpath(full, path)
            _, ext = os.path.splitext(name)
            if st > (1 << 20) and ext.lower() not in TEXT_EXT_OK:
                continue
            try:
                with open(full, "rb") as f:
                    data = f.read(1 << 20)
            except OSError:
                continue
            before = len(problems)
            scan_bytes_for_secrets(
                data, f"{rel}/{os.path.relpath(full, path)}",
                details, problems)
            secret_hits += len(problems) - before
    details.append(f"{rel}: tree {nfiles} files, "
                   f"{total / (1024 * 1024):.1f} MiB")
    if total > args.max_mb * 1024 * 1024:
        problems.append(f"{rel}: tree larger than {args.max_mb} MiB")
    is_rootfs = os.path.isdir(os.path.join(path, "etc"))
    is_boot = any(k in boot_hits for k in ("BOOT.SCR", "IMAGE"))
    if not is_rootfs and not is_boot:
        problems.append(f"{rel}: neither boot files (boot.scr/Image) nor "
                        "rootfs marker (etc/) found")
        return
    if is_boot or args.expect_boot:
        for want in BOOT_FILES:
            if want in boot_hits:
                details.append(f"{rel}: boot file present: "
                               f"{boot_hits[want]}")
            else:
                problems.append(f"{rel}: boot file missing: {want}")
    if is_rootfs or args.expect_rootfs:
        for marker in ("etc",):
            if os.path.isdir(os.path.join(path, marker)):
                details.append(f"{rel}: rootfs marker present: {marker}/")
            else:
                problems.append(f"{rel}: rootfs marker missing: {marker}/")
        for opt in ("sbin/init", "etc/fstab", "etc/os-release"):
            if os.path.exists(os.path.join(path, opt)):
                details.append(f"{rel}: rootfs file present: {opt}")
    if secret_hits == 0:
        details.append(f"{rel}: no-secrets scan clean")


def default_targets(root):
    env = os.environ.get("IMAGE_UNDER_TEST", "")
    if env:
        return [env]
    out = []
    build_out = os.path.join(root, "build", "out")
    if os.path.isdir(build_out):
        for name in sorted(os.listdir(build_out)):
            if name.endswith(".img"):
                out.append(os.path.join(build_out, name))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate RG35XX H SD images.")
    ap.add_argument("targets", nargs="*", default=None,
                    help=".img files or mounted/staging dirs "
                         "(default: $IMAGE_UNDER_TEST or build/out/*.img).")
    ap.add_argument("--root", default=None)
    ap.add_argument("--min-mb", type=float, default=512.0)
    ap.add_argument("--max-mb", type=float, default=8192.0)
    ap.add_argument("--skip-bootfs", action="store_true",
                    help="Skip FAT boot-file listing (GPT skeletons).")
    ap.add_argument("--relaxed-uuids", action="store_true",
                    help="Skip PARTUUID equality (custom --disk-guid builds).")
    ap.add_argument("--expect-boot", action="store_true",
                    help="Require boot files even in rootfs-looking trees.")
    ap.add_argument("--expect-rootfs", action="store_true",
                    help="Require etc/ even in boot-looking trees.")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    args.root = repo_root(args.root)

    # NB: nargs="*" yields [] (not None) when no positionals are given,
    # so an explicit empty check selects the default search.
    targets = args.targets or default_targets(args.root)
    details, problems = [], []
    if not targets:
        return emit("image", NOTRUN,
                    ["no .img under build/out/ and $IMAGE_UNDER_TEST unset "
                     "(assemble first: build/image/assemble-image.sh)"],
                    json_mode=args.json)
    for t in targets:
        p = t if os.path.isabs(t) else os.path.join(args.root, t)
        if not os.path.exists(p):
            return emit("image", BLOCKED, [f"target not found: {t}"],
                        target=t, json_mode=args.json)
        if os.path.isdir(p):
            check_tree(p, details, problems, args)
        else:
            check_image_file(p, details, problems, args)
    details.append(f"checked {len(targets)} target(s), "
                   f"{len(problems)} problem(s)")
    if problems:
        details.extend(f"PROBLEM: {p}" for p in problems)
        return emit("image", FAIL, details, json_mode=args.json)
    return emit("image", PASS, details, json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
