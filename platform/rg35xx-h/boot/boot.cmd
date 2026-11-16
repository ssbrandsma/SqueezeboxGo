# boot.cmd — U-Boot boot script source for RG35XX H (FAT partition root).
# Build: mkimage -C none -A arm64 -T script -d boot.cmd boot.scr
# Loads: Image (kernel), dtb.img (board DTB), optional display overlay.
# PARTUUIDs must match build/image/partitions.sfdisk (fixed for repro builds).

setenv bootargs 'console=ttyS0,115200n8 root=PARTUUID=0a1b2c3d-0002-4000-8000-000000000000 rootwait rw earlycon=sunxi-uart,0x05000000 loglevel=4 coherent_pool=1M'

# Status LED (PI11 = U-Boot gpio 267) ON: U-Boot proper is alive and boot.scr
# runs. Needs CONFIG_CMD_GPIO (uboot-rg35xx-h-common-fragment.conf).
# Power LED (PI12) has been on since SPL; kernel heartbeat takes over later.
gpio set 267

load mmc 0:1 ${kernel_addr_r} Image
load mmc 0:1 ${fdt_addr_r} dtb.img
fdt addr ${fdt_addr_r}

# Optional OOT display overlay (WP2, lands as overlays/rg35xx-h-display.dtbo).
if load mmc 0:1 ${ramdisk_addr_r} overlays/rg35xx-h-display.dtbo; then
    fdt apply ${ramdisk_addr_r}
fi

booti ${kernel_addr_r} - ${fdt_addr_r}
