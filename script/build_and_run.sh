#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wallpaper Enhancer"
EXECUTABLE="WallpaperEnhancer"
BUNDLE_ID="garden.bath.wallpaper-enhancer"
SIGNING_IDENTITY="${WALLPAPER_ENHANCER_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$ROOT_DIR/.local/signing-identity" ]]; then
  IFS= read -r SIGNING_IDENTITY < "$ROOT_DIR/.local/signing-identity" || true
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Configure a stable code-signing identity in .local/signing-identity or WALLPAPER_ENHANCER_SIGNING_IDENTITY. See docs/development.md." >&2
  exit 1
fi
/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F "$SIGNING_IDENTITY" >/dev/null || { echo "Required code-signing identity is unavailable." >&2; exit 1; }
BUILD_ROOT="${WALLPAPER_ENHANCER_BUILD_DIR:-$HOME/Library/Caches/garden.bath.wallpaper-enhancer/Build}"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
mkdir -p "$BUILD_ROOT"
cd "$ROOT_DIR"
if [[ "$MODE" != "--package" ]]; then
  STATE="$HOME/Library/Application Support/$BUNDLE_ID/state.json"
  if pgrep -x "$EXECUTABLE" >/dev/null && [[ -f "$STATE" ]] && /usr/bin/grep -Eq '"status"[[:space:]]*:[[:space:]]*"(preparing|enhancing|saving)"' "$STATE"; then
    echo "An enhancement is in progress. Let it finish before rebuilding or restarting." >&2
    exit 1
  fi
  pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
fi
swift build --scratch-path "$BUILD_ROOT/SwiftPM"
BUILD_BINARY="$(swift build --scratch-path "$BUILD_ROOT/SwiftPM" --show-bin-path)/$EXECUTABLE"
STAGING="$(mktemp -d "$BUILD_ROOT/app-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
CONTENTS="$STAGING/$APP_NAME.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_BINARY" "$CONTENTS/MacOS/$EXECUTABLE"
chmod +x "$CONTENTS/MacOS/$EXECUTABLE"
"$ROOT_DIR/script/build_icon.sh" "$CONTENTS/Resources"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>App Icon</string>
<key>CFBundleIconName</key><string>App Icon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" --options runtime --timestamp=none "$STAGING/$APP_NAME.app"
/usr/bin/codesign --verify --strict --verbose=2 "$STAGING/$APP_NAME.app"
/usr/bin/codesign -dvvv -r- "$STAGING/$APP_NAME.app" 2>&1
if [[ -e "$APP_BUNDLE" ]]; then rm -rf "$APP_BUNDLE"; fi
mv "$STAGING/$APP_NAME.app" "$APP_BUNDLE"
case "$MODE" in
  --package) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$EXECUTABLE" >/dev/null ;;
  --logs|--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" ;;
  *) echo "usage: $0 [run|--package|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
