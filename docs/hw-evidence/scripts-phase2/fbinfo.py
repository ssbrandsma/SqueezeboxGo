import fcntl, struct
FBIOGET_VSCREENINFO = 0x4600
FBIOGET_FSCREENINFO = 0x4602
with open("/dev/fb0", "rb") as f:
    vbuf = fcntl.ioctl(f, FBIOGET_VSCREENINFO, bytes(160))
    v = struct.unpack("<40I", vbuf)
    names = ["xres","yres","xres_virtual","yres_virtual","xoffset","yoffset",
             "bpp","grayscale","red_o","red_l","red_m","green_o","green_l","green_m",
             "blue_o","blue_l","blue_m","transp_o","transp_l","transp_m",
             "nonstd","activate","height_mm","width_mm","accel_flags","pixclock_ps",
             "left_margin","right_margin","upper_margin","lower_margin",
             "hsync_len","vsync_len","sync","vmode","rotate","colorspace"] + [f"reserved{i}" for i in range(4)]
    for n, val in zip(names, v):
        print(f"{n}={val}")
    fbuf = fcntl.ioctl(f, FBIOGET_FSCREENINFO, bytes(80))
    fix = struct.unpack("<16sQIIIIHHH2xIQIIHHH", fbuf)
    print("fix_id=%r" % fix[0])
    for n, val in zip(["smem_start","smem_len","type","type_aux","visual","xpanstep","ypanstep","ywrapstep","line_length","mmio_start","mmio_len","accel","caps","res0","res1"], fix[1:]):
        print(f"{n}={val:#x}" if isinstance(val,int) and ("start" in n or "len" in n) else f"{n}={val}")
