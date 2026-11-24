#!/bin/sh
set -eu
cd "$(dirname "$0")"
LUNA_BIN=${LUNA_BIN:-luna}
cat source/lessons.lua source/engine.lua source/ui.lua > PrecalculusStudio.lua
if command -v luac >/dev/null 2>&1; then luac -p PrecalculusStudio.lua; fi
"$LUNA_BIN" PrecalculusStudio.lua PrecalculusStudio.tns
