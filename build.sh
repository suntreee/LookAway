#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_NAME="LookAway"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/LookAway"
DMG_PATH="$DIST_DIR/LookAway.dmg"
PYTHON_BIN="/Users/suntree/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="python3"
fi

rm -rf "$APP_DIR" "$DMG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR"
mkdir -p "$BUILD_DIR/ModuleCache"

"$PYTHON_BIN" "$ROOT/tools/make_app_icon.py"
iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"

swiftc \
  "$ROOT/Sources/main.swift" \
  -o "$EXECUTABLE" \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  -framework AppKit

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"
chmod +x "$EXECUTABLE"
touch "$APP_DIR" "$APP_DIR/Contents" "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources/AppIcon.icns"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Built:"
echo "  $APP_DIR"
echo "  $DMG_PATH"
