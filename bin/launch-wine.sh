#!/usr/bin/env bash
# launch-wine.sh <game-dir> <exe-path>
set -euo pipefail
cd "$1"
exec wine "$2"
