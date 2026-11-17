#!/usr/bin/env python3
"""Apply LocalPlayerStatus wiring to a StandaloneRadioApplet.lua copy.

Reads the pristine applet file, applies exact-match insertions, writes the
patched file with CRLF preserved. Fails loudly unless every anchor matches
exactly once. Also used to regenerate the peer-diff artifact.
"""
import sys

SRC = "/tmp/applet-src/StandaloneRadioApplet.lua"
DST = "/tmp/applet-src/StandaloneRadioApplet.patched.lua"

with open(SRC, "rb") as fh:
    text = fh.read().decode("utf-8").replace("\r\n", "\n")

edits = []

# E1: require the new module alongside the other applet requires.
edits.append((
    'local StandaloneBaseNowPlaying = require("applets.StandaloneRadio.StandaloneBaseNowPlaying")\n',
    'local StandaloneBaseNowPlaying = require("applets.StandaloneRadio.StandaloneBaseNowPlaying")\n'
    'local LocalPlayerStatus = require("applets.StandaloneRadio.LocalPlayerStatus")\n',
))

# E2: instantiate after the Base publisher, before native navigation.
anchor = "\tself.nativeNowPlaying = NativeNowPlaying.new({\n"
inst = (
    "\t-- Local fallback: stage the native Player while Base is absent.\n"
    "\t-- Yields automatically once the Base client holds a session.\n"
    "\tself.localPlayerStatus = LocalPlayerStatus.new({\n"
    "\t\tlog = log,\n"
    "\t\tappletManager = appletManager,\n"
    "\t\tbaseClient = self.baseNowPlaying,\n"
    "\t\tisPlaybackOwner = function()\n"
    "\t\t\treturn self.streamPlayer and self.streamPlayer.ownsPlayback == true\n"
    "\t\tend,\n"
    "\t\tonFirstPush = function(stationGeneration)\n"
    "\t\t\t-- Navigate without onStage: subscribing here would pull the\n"
    "\t\t\t-- remote library's empty playlist over our synthesized state.\n"
    "\t\t\tself.nativeNowPlaying:request(stationGeneration)\n"
    "\t\tend,\n"
    "\t})\n"
    "\n"
)
edits.append((anchor, inst + anchor))

# E3: mirror every Base-publisher callback into the local synthesizer.
pairs = [
    ("\t\t\t\tself.baseNowPlaying:release()\n",
     "\t\t\t\tself.baseNowPlaying:release()\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:release() end\n"),
    ("\t\t\t\tself.baseNowPlaying:updateTimedMetadata(event, station, stationGeneration)\n",
     "\t\t\t\tself.baseNowPlaying:updateTimedMetadata(event, station, stationGeneration)\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:updateTimedMetadata(event, station, stationGeneration) end\n"),
    ("\t\t\t\tself.baseNowPlaying:updateState(state, station, stationGeneration)\n",
     "\t\t\t\tself.baseNowPlaying:updateState(state, station, stationGeneration)\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:updateState(state, station, stationGeneration) end\n"),
    ("\t\t\t\tself.baseNowPlaying:updateMetadata(title, station, stationGeneration)\n",
     "\t\t\t\tself.baseNowPlaying:updateMetadata(title, station, stationGeneration)\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:updateMetadata(title, station, stationGeneration) end\n"),
    ("\t\t\t\tself.baseNowPlaying:activate(station, stationGeneration)\n",
     "\t\t\t\tself.baseNowPlaying:activate(station, stationGeneration)\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:activate(station, stationGeneration) end\n"),
    ("\t\t\t\tself.baseNowPlaying:updateStation(station, stationGeneration)\n",
     "\t\t\t\tself.baseNowPlaying:updateStation(station, stationGeneration)\n"
     "\t\t\t\tif self.localPlayerStatus then self.localPlayerStatus:updateStation(station, stationGeneration) end\n"),
]
edits.extend(pairs)

# E3b: onPosition has a different shape (Base takes position only for
# episodes; local takes position+duration ms).
edits.append((
    "            onPosition = function(position, station, stationGeneration)\n"
    "                self.baseNowPlaying:updatePosition(position,station,stationGeneration)\n",
    "            onPosition = function(position, station, stationGeneration)\n"
    "                self.baseNowPlaying:updatePosition(position,station,stationGeneration)\n"
    "                if self.localPlayerStatus then self.localPlayerStatus:updatePosition(position, station and station.duration_ms, stationGeneration) end\n",
))

# E4: release synthesis when the applet is freed.
edits.append((
    "\tif self.nativeNowPlaying then self.nativeNowPlaying:shutdown() end\n",
    "\tif self.nativeNowPlaying then self.nativeNowPlaying:shutdown() end\n"
    "\tif self.localPlayerStatus then self.localPlayerStatus:release() end\n",
))

for i, (find, replace) in enumerate(edits):
    count = text.count(find)
    if count != 1:
        print("anchor %d matches %d times (want 1): %r" % (i, count, find[:80]))
        sys.exit(1)
    text = text.replace(find, replace)

with open(DST, "wb") as fh:
    fh.write(text.replace("\n", "\r\n").encode("utf-8"))
print("patched OK ->", DST)
