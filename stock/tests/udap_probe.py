#!/usr/bin/env python3
"""udap_probe.py — solicit + decode SlimProto/Udap discovery responses.

Sends a broadcast adv_discover (method 0x0009) to UDP 17784 and prints
every response's TLVs (device status/id, hw rev, firmware, device
type/name). Used to verify the platform identity a Jive player
advertises on the wire (device type + id come from
LocalPlayer:setDeviceType).

Wire format: ralph-irving/squeezeplay@758bc11
share/jive/net/Udap.lua (createUdap / createAdvancedDiscoverResponse).

Usage: python3 udap_probe.py [--expect-mac 68:8f:c9:05:ff:9f] [--timeout 5]
Exit 0 when at least one response arrives, 1 on timeout.
"""
import socket
import struct
import sys

PORT = 0x4578  # 17784 (Udap.lua: local PORT)
TLV_NAMES = {
    0x02: "devName", 0x03: "devType", 0x05: "ip",
    0x09: "firmware", 0x0A: "hwRev", 0x0B: "devId",
    0x0C: "devStatus", 0x0D: "uuid",
}


def build_adv_discover(srcmac, seq=1):
    sm = bytes(int(srcmac[i:i + 2], 16) for i in range(0, 12, 2))

    def num(v, n):
        return v.to_bytes(n, "big")

    return b"".join([
        num(1, 1), num(0x01, 1), bytes(6),
        num(0x0001, 2), sm, num(seq, 2),
        num(0xC001, 2), num(0x01, 1),
        num(0x0001, 2), num(0x0001, 2),
        num(0x0009, 2),
    ])


def parse_response(data):
    if len(data) < 28:
        return None
    # fixed 27-byte head: bcast(1) dtype(1) dmac(6) stype(2) smac(6)
    # seq(2) udaptype(2) flags(1) class(4) method(2)
    head = struct.unpack(">BB6s2s6sHHB4sH", data[:27])
    seq, flags, method = head[5], head[7], head[9]
    tlvs = {}
    off = 27
    while off + 2 <= len(data):
        t, ln = data[off], data[off + 1]
        val = data[off + 2:off + 2 + ln]
        if len(val) < ln:
            break
        tlvs[TLV_NAMES.get(t, "0x%02x" % t)] = val
        off += 2 + ln
    smac = ":".join("%02x" % b for b in head[4])
    return {"seq": seq, "flags": flags, "method": method,
            "srcmac": smac, "tlvs": tlvs}


def main(argv):
    expect = None
    timeout = 5.0
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--expect-mac" and args:
            expect = args.pop(0).lower()
        elif a == "--timeout" and args:
            timeout = float(args.pop(0))
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(timeout)
    s.bind(("0.0.0.0", 0))
    # source mac: ours is irrelevant, use a locally-administered value
    s.sendto(build_adv_discover("020000000001"),
             ("255.255.255.255", PORT))
    found = 0
    try:
        while True:
            try:
                data, addr = s.recvfrom(2048)
            except socket.timeout:
                break
            r = parse_response(data)
            if r is None:
                continue
            found += 1
            mark = ""
            if expect and r["srcmac"] == expect:
                mark = "  <-- EXPECTED DEVICE"
            print("from %s mac=%s method=0x%04x%s" % (
                addr[0], r["srcmac"], r["method"], mark))
            for k, v in r["tlvs"].items():
                try:
                    txt = v.decode("ascii")
                except ValueError:
                    txt = v.hex()
                print("    %s = %s" % (k, txt))
    finally:
        s.close()
    if found == 0:
        print("no Udap responses (player may be server-connected: "
              "connected players stay silent by design)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
