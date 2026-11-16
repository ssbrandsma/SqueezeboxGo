import mmap, hashlib, struct, fcntl
FB='/dev/fb0'
W,H=1280,1024
STRIDE=2560
N=W*H*2
FBIOGET_VSCREENINFO=0x4600
with open(FB,'r+b') as f:
    vinfo=fcntl.ioctl(f,FBIOGET_VSCREENINFO,b'\x00'*160)
    xres,yres=struct.unpack('II',vinfo[0:8])
    xv,yv,xo,yo=struct.unpack('IIII',vinfo[8:24])
    bpp=struct.unpack('I',vinfo[24:28])[0]
    print(f"GEOM xres={xres} yres={yres} xvirt={xv} yvirt={yv} xoff={xo} yoff={yo} bpp={bpp}", flush=True)
    mm=mmap.mmap(f.fileno(),N)
    orig=bytes(mm)
    print(f"ORIG sha={hashlib.sha256(orig).hexdigest()} len={len(orig)}", flush=True)
    pat=bytearray(N)
    for y in range(H):
        base=y*STRIDE
        for x in range(0,W*2,2):
            v=((x//2)&0x1F)|(((y&0x3F)<<5)&0x7E0)|((((x//2+y)&0x1F)<<11)&0xF800)
            pat[base+x]=v&0xFF; pat[base+x+1]=(v>>8)&0xFF
    pat=bytes(pat)
    print(f"PAT sha={hashlib.sha256(pat).hexdigest()}", flush=True)
    mm.seek(0); mm.write(pat)
    mm.seek(0); rb=mm.read(N)
    print(f"READBACK sha={hashlib.sha256(rb).hexdigest()} IDENTICAL={rb==pat}", flush=True)
    mm.seek(0); mm.write(orig)
    mm.seek(0); rb2=mm.read(N)
    print(f"RESTORE sha={hashlib.sha256(rb2).hexdigest()} IDENTICAL={rb2==orig}", flush=True)
    mm.close()
print("FB_PHASE3_DONE")
