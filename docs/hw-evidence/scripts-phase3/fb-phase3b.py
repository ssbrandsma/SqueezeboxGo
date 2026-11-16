import mmap, hashlib, struct, fcntl
FB='/dev/fb0'; W,H=1280,1024; STRIDE=2560; N=W*H*2
with open(FB,'r+b') as f:
    mm=mmap.mmap(f.fileno(),N)
    orig=bytes(mm)
    print(f"ORIG sha={hashlib.sha256(orig).hexdigest()}", flush=True)
    # distinct pattern: byte-inverted gradient + frame counter stripe
    pat=bytearray(N)
    for y in range(H):
        base=y*STRIDE
        for x in range(0,W*2,2):
            v=(~(((x//2)&0x1F)|(((y&0x3F)<<5)&0x7E0)|((((x//2+y)&0x1F)<<11)&0xF800)))&0xFFFF
            pat[base+x]=v&0xFF; pat[base+x+1]=(v>>8)&0xFF
    # red marker stripe rows 100..103
    for y in range(100,104):
        for x in range(0,W*2,2):
            pat[y*STRIDE+x]=0x00; pat[y*STRIDE+x+1]=0xF8
    pat=bytes(pat)
    print(f"PAT sha={hashlib.sha256(pat).hexdigest()} DIFFERS_FROM_ORIG={pat!=orig}", flush=True)
    mm.seek(0); mm.write(pat)
    mm.seek(0); rb=mm.read(N)
    print(f"READBACK sha={hashlib.sha256(rb).hexdigest()} IDENTICAL={rb==pat}", flush=True)
    mm.seek(0); mm.write(orig)
    mm.seek(0); rb2=mm.read(N)
    print(f"RESTORE sha={hashlib.sha256(rb2).hexdigest()} IDENTICAL={rb2==orig}", flush=True)
    mm.close()
print("FB_PHASE3B_DONE")
