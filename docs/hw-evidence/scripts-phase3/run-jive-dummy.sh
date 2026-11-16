#!/bin/sh
# Phase 3 control: dummy video driver, separates video from core boot
export HOME=/home/muse/squeezebox-dev/jive-home
export LD_LIBRARY_PATH=/home/muse/squeezebox-dev/fbcon-lib:/home/muse/squeezebox-dev/sp-stage/opt/squeezeplay/lib
export SDL_VIDEODRIVER=dummy
cd /home/muse/squeezebox-dev/sp-stage/opt/squeezeplay/bin || exit 1
exec stdbuf -o0 -e0 ./jive "$@"
