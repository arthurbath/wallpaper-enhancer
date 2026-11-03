#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${WALLPAPER_ENHANCER_BUILD_DIR:-$HOME/Library/Caches/garden.bath.wallpaper-enhancer/Build}"
cd "$ROOT_DIR"
swift test --scratch-path "$BUILD_ROOT/SwiftPM" "$@"
