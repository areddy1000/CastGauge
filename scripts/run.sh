#!/bin/zsh
# Build a debug bundle and open it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh" debug
pkill -x CastGauge 2>/dev/null || true
open "$ROOT/dist/CastGauge.app"
