# Hardware (RG35XX H, H700)

Starting assumptions (verify against DTS/kernel/evidence):

- SoC Allwinner H700 (H616 class + ATF BL31), Cortex-A53 x4, ~1 GB RAM, Mali-G31.
- 3.5" IPS 640x480 4:3, no touch. Panel: `fog_fj035fhd05_v1`-class 640x480 RGB,
  PWM ch0 backlight (muOS sunxi.dts timing reference; mainline DTS has no panel nodes).
- Controls: D-pad, ABXY, Start/Select, L1/R1/L2/R2, 2 clickable sticks
  (mainline: 4ch adc-joystick via gpio-mux+gpadc + gpio-keys).
- Audio: internal sun4i-codec LINEOUT + hp-detect; speakers + 3.5 mm jack.
- Net: RTL8821CS SDIO Wi-Fi (mmc1, PG15-19 pwrseq) + BT (uart1). Driver: RTW88_8821CS.
- Power: AXP717 (battery/ADC); USB-C charging + OTG/host; 2nd USB; dual microSD.
- UART debug header exists; verify pinout/voltage before connecting
  (ref: steward-fu.github.io RG35XX H UART page).

DDR3 vs DDR4 units: ship both image variants; unit ID method TBD on hardware.
Distinguish SoC capability vs driver vs firmware vs hardware-verified in all claims.
