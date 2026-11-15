#!/usr/bin/env python3
"""clamp-fat.py — pin mkfs.vfat volume-label timestamps to $SOURCE_DATE_EPOCH.

Why this exists: mkfs.vfat (dosfstools, no SOURCE_DATE_EPOCH support as of
4.2) stamps the volume-label directory entry with wall-clock time, so two
fresh filesystems differ in 4 bytes (creation + modification time). mtools
(mcopy, >= 4.0.27) honors SOURCE_DATE_EPOCH itself, so only the label entry
needs clamping. Times are derived from the epoch in UTC so builds are
identical in every host timezone (assemble-image.sh also exports TZ=UTC0).

Usage: clamp-fat.py --image FILE --epoch N
"""
import argparse
import datetime
import struct
import sys


def dos_datetime(epoch):
    dt = datetime.datetime.fromtimestamp(epoch, tz=datetime.timezone.utc)
    if not 1980 <= dt.year <= 2107:
        raise ValueError(f"epoch {epoch} out of FAT date range")
    date = ((dt.year - 1980) << 9) | (dt.month << 5) | dt.day
    time = (dt.hour << 11) | (dt.minute << 5) | (dt.second // 2)
    return time, date


def clamp(path, epoch):
    with open(path, "r+b") as f:
        bpb = f.read(512)
        if bpb[510:512] != b"\x55\xaa":
            raise ValueError("not a FAT boot sector (bad signature)")
        bps = struct.unpack_from("<H", bpb, 11)[0]
        rsv = struct.unpack_from("<H", bpb, 14)[0]
        fats = bpb[16]
        spf16 = struct.unpack_from("<H", bpb, 22)[0]
        spf32 = struct.unpack_from("<I", bpb, 36)[0]
        spf = spf16 or spf32
        if bps == 0 or fats == 0 or spf == 0:
            raise ValueError("implausible BPB geometry")
        root_off = (rsv + fats * spf) * bps
        f.seek(root_off)
        cluster = f.read(bps)
        mtime, mdate = dos_datetime(epoch)
        for i in range(0, len(cluster), 32):
            e = bytearray(cluster[i:i + 32])
            if e[0] == 0x00:
                break  # end of directory
            if e[0] == 0xE5:
                continue  # deleted
            if e[11] & 0x08 and not e[11] & 0x10:
                # Volume label (not a directory): pin all four stamps.
                e[13] = 0  # creation tenths (mkfs leaves 0)
                struct.pack_into("<H", e, 14, mtime)
                struct.pack_into("<HH", e, 16, mdate, mdate)  # cdate, adate
                struct.pack_into("<HH", e, 22, mtime, mdate)  # wtime, wdate
                f.seek(root_off + i)
                f.write(e)
                print(f"clamped label {bytes(e[:11]).decode('ascii', 'replace')!r} "
                      f"to {mtime:04x}/{mdate:04x} (epoch {epoch} UTC)")
                return 0
        raise ValueError("no volume-label entry in root directory")


def main(argv=None):
    ap = argparse.ArgumentParser(description="pin FAT label timestamps to epoch")
    ap.add_argument("--image", required=True)
    ap.add_argument("--epoch", required=True, type=int)
    a = ap.parse_args(argv)
    try:
        return clamp(a.image, a.epoch)
    except ValueError as ex:
        print(f"clamp-fat.py: ERROR: {ex}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
