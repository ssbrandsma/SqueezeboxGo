import fcntl, struct
FBIOGET_FSCREENINFO = 0x4602
with open("/dev/fb0", "rb") as f:
    fbuf = fcntl.ioctl(f, FBIOGET_FSCREENINFO, bytes(128))
    fix = struct.unpack("<16sQIIIIHHH2xI4xQIIHHH", fbuf[:78])
    print("fix_id=%r" % fix[0])
    for n, val in zip(["smem_start","smem_len","type","type_aux","visual","xpanstep","ypanstep","ywrapstep","line_length","mmio_start","mmio_len","accel","caps","res0","res1"], fix[1:]):
        print(f"{n}={val:#x}" if ("start" in n or "len" in n) else f"{n}={val}")
