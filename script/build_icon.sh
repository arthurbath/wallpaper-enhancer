#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${WALLPAPER_ENHANCER_BUILD_DIR:-$HOME/Library/Caches/garden.bath.wallpaper-enhancer/Build}"
DESTINATION="${1:-$BUILD_ROOT/IconAssets}"
mkdir -p "$BUILD_ROOT" "$DESTINATION"
STAGING="$(mktemp -d "$BUILD_ROOT/icon-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
xcrun actool "$ROOT_DIR/Resources/App Icon.icon" \
  --compile "$DESTINATION" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon "App Icon" --target-device mac \
  --output-partial-info-plist "$STAGING/Info.plist" --output-format human-readable-text
[[ -f "$DESTINATION/App Icon.icns" && -f "$DESTINATION/Assets.car" ]] || {
  echo "The supplied Icon Composer document did not compile into complete app resources." >&2
  exit 1
}
