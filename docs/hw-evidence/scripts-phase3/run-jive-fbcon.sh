#!/bin/sh
# Phase 3 headless jive: fbcon video probe, staging HOME
export HOME=/home/muse/squeezebox-dev/jive-home
export LD_LIBRARY_PATH=/home/muse/squeezebox-dev/fbcon-lib:/home/muse/squeezebox-dev/sp-stage/opt/squeezeplay/lib
unset SDL_VIDEODRIVER
cd /home/muse/squeezebox-dev/sp-stage/opt/squeezeplay/bin || exit 1
exec stdbuf -o0 -e0 ./jive "$@"
