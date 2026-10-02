#!/usr/bin/env bash
# launch-native.sh <game-dir> <binary-path> — bypasses Steam's launcher for
# titles with a working native Linux binary that Steam insists on
# Proton-wrapping anyway (no ownership/DRM handshake needed for native ELFs).
set -euo pipefail
cd "$1"
exec "$2"
