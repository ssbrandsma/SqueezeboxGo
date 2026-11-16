# jive-env.sh — environment for running Jive on the STOCK system.
#
# Sourced by run-jive.sh (and only by it). Copy to the install dir and
# edit the copy; every knob is documented. Values here are STARTING
# POINTS from docs/hardware.md verified facts — confirm each against
# your own stock-probe.sh tarball before first run.
#
# SPDX-License-Identifier: GPL-2.0-or-later

# --- Jive binary ------------------------------------------------------
# Where the Jive executable lives. run-jive.sh checks these in order and
# refuses to stop the frontend until one of them exists:
#   1. $JIVE_BIN (if you export it)
#   2. $BUNDLE_ROOT/jive/jive (drop a build into the bundle's jive/ dir)
#   3. /opt/squeezeplay/bin/jive (mainline cross-build install layout)
# JIVE_BIN=
JIVE_BIN="${JIVE_BIN:-}"

# --- Gaming frontend unit ---------------------------------------------
# The systemd unit run-jive.sh stops. NEVER defaults: it must come from
# --frontend-unit, $FRONTEND_UNIT, or frontend-unit.txt, and that value
# must have been identified from YOUR probe tarball (90-frontend-hunt.txt
# + 50-processes-services.txt). Leave empty here on purpose.
FRONTEND_UNIT="${FRONTEND_UNIT:-}"

# --- SDL video ---------------------------------------------------------
# Stock kernel has /dev/fb0 and NO /dev/dri (verified), so KMSDRM is out.
# SDL 1.2 on fbcon is the expected path; which SDL the stock image ships
# is in your probe tarball (20-sdl.txt + 80-packages.txt).
SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-fbcon}"
SDL_FBDEV="${SDL_FBDEV:-/dev/fb0}"
# Physical LCD is 640x480; fb virtual size was 1280x1024 at inventory —
# check 10-framebuffer.txt before assuming stride/orientation.
SDL_FB_BROKEN_MODES="${SDL_FB_BROKEN_MODES:-0}"
export SDL_VIDEODRIVER SDL_FBDEV SDL_FB_BROKEN_MODES

# --- SDL audio ----------------------------------------------------------
# Verified cards: 0 audiocodec, 1 ahubdam, 2 ahubhdmi. Internal speaker
# is audiocodec; the PCM was OCCUPIED at inventory, so run-jive.sh warns
# when fuser sees a holder.
SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
ALSA_DEVICE="${ALSA_DEVICE:-hw:CARD=audiocodec,DEV=0}"
# Jive/ALSA knobs from the interface contracts (audio ownership):
USEALSA_DEVICE="${USEALSA_DEVICE:-$ALSA_DEVICE}"
export SDL_AUDIODRIVER ALSA_DEVICE USEALSA_DEVICE
# SAMPLE_SIZE / BUFFER / PERIOD / NOMMAP / PCM_TIMEOUT: leave at Jive
# defaults until 30-alsa.txt + a first playback attempt say otherwise.
# SQUEEZEPLAY_NOPLAYBACK=1 forces UI-only (no ALSA open) for display tests.
SQUEEZEPLAY_NOPLAYBACK="${SQUEEZEPLAY_NOPLAYBACK:-0}"
export SQUEEZEPLAY_NOPLAYBACK

# --- Input ---------------------------------------------------------------
# Discover by NAME (numbers shift): axp2202-pek, ANBERNIC-keys,
# dierct-keys-polled (sic, vendor typo). See 40-input.txt.
# evdev node resolution happens in the mapper, not here.

# --- Misc -----------------------------------------------------------------
# Keep Jive's writes inside the bundle (no ~/.jive litter on stock).
JIVE_HOME_DIR="${JIVE_HOME_DIR:-$BUNDLE_ROOT/state/jive-home}"
export JIVE_HOME_DIR
