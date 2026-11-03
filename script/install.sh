#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build_and_run.sh" --package
BUILD_ROOT="${WALLPAPER_ENHANCER_BUILD_DIR:-$HOME/Library/Caches/garden.bath.wallpaper-enhancer/Build}"
SOURCE="$BUILD_ROOT/Wallpaper Enhancer.app"
DESTINATION="/Applications/Wallpaper Enhancer.app"
STAGING="$(mktemp -d /Applications/.wallpaper-enhancer-install.XXXXXX)"
BACKUP=""
cleanup() {
  if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then
    echo "Recovery bundle preserved: $BACKUP" >&2
  else
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE" "$STAGING/Wallpaper Enhancer.app"
/usr/bin/codesign --verify --strict "$STAGING/Wallpaper Enhancer.app"
if [[ -e "$DESTINATION" ]]; then
  STATE="$HOME/Library/Application Support/garden.bath.wallpaper-enhancer/state.json"
  if pgrep -x WallpaperEnhancer >/dev/null && [[ -f "$STATE" ]] && /usr/bin/grep -Eq '"status"[[:space:]]*:[[:space:]]*"(preparing|enhancing|saving)"' "$STATE"; then
    echo "An enhancement is in progress. Let it finish before installing an update." >&2
    exit 1
  fi
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")"
  [[ "$EXISTING_ID" == "garden.bath.wallpaper-enhancer" ]] || { echo "An unrelated app uses this name. Installation stopped." >&2; exit 1; }
  OLD_HASH="$(/usr/bin/codesign -dvv "$DESTINATION" 2>&1 | /usr/bin/grep '^CDHash=' || true)"
  NEW_HASH="$(/usr/bin/codesign -dvv "$STAGING/Wallpaper Enhancer.app" 2>&1 | /usr/bin/grep '^CDHash=' || true)"
  if [[ -n "$OLD_HASH" && "$OLD_HASH" == "$NEW_HASH" ]] && /usr/bin/codesign --verify --strict "$DESTINATION"; then
    echo "The installed signed app already matches this build. Preserved in place."
    exit 0
  fi
  pkill -x WallpaperEnhancer >/dev/null 2>&1 || true
  BACKUP="$STAGING/Previous.app"
  mv "$DESTINATION" "$BACKUP"
fi
if ! mv "$STAGING/Wallpaper Enhancer.app" "$DESTINATION"; then
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$DESTINATION"
  exit 1
fi
if ! /usr/bin/codesign --verify --strict "$DESTINATION"; then
  mv "$DESTINATION" "$STAGING/Failed.app"
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$DESTINATION"
  echo "Installation verification failed. Previous app restored." >&2
  exit 1
fi
/usr/bin/open -n "$DESTINATION"
sleep 2
if ! pgrep -x WallpaperEnhancer >/dev/null; then
  mv "$DESTINATION" "$STAGING/Failed.app"
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$DESTINATION"
  echo "The new app did not remain running. Previous app restored." >&2
  exit 1
fi
if [[ -n "$BACKUP" ]]; then
  TRASH="$HOME/.Trash/Wallpaper Enhancer-before-$(date +%Y%m%d-%H%M%S).app"
  if ! mv "$BACKUP" "$TRASH"; then
    RECOVERY="/Applications/Wallpaper Enhancer-Recovery-$(date +%Y%m%d-%H%M%S).app"
    mv "$BACKUP" "$RECOVERY"
    echo "Old-bundle cleanup failed. Recovery bundle: $RECOVERY" >&2
    exit 1
  fi
fi
echo "Installed and verified: $DESTINATION"
