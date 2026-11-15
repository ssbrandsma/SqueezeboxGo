# Audio

Chain: source → decoder → PCM → ALSA → sun4i-codec / snd-usb-audio.

- Backend: `decode_alsa.c` + `decode_alsa_backend.c` (sp tree): S32/S24/S24_3LE/S16
  fallback, PCM_WAIT_TIMEOUT, >96 kHz prestart, 352/384 kHz stall fix.
- No resampling/bit-depth conversion beyond what the driver requires.
- Mixer/routing: sun4i-codec LINEOUT, speaker amp, hp-detect switch, mute/pop control
  (exact controls TBD from platform kernel; see `audio/alsa/` in WP1).
- USB DAC: `snd-usb-audio`, hotplug detect, fallback to internal, safe unplug recovery.
- Ownership: one source holds ALSA at a time (`audio-owner`); volume/mute consistent;
  Now Playing updates on switch; crash releases device.
- Validation: `aplay/arecord`, `/proc/asound`, PCM format matrix, underrun recovery,
  native-rate checks. Bit-perfect only if full path verified.
