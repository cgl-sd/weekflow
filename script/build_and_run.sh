#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Weekflow"
BUNDLE_ID="com.weekflow.app"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${WEEKFLOW_VERSION:-0.5.0}"
BUILD_NUMBER="${WEEKFLOW_BUILD_NUMBER:-1}"
BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_CONFIGURATION="release"
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/01_workspace"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$PACKAGE_DIR/Resources/WeekflowIcon.icns"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$PACKAGE_DIR"
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_CONTENTS/Resources"
cp "$ICON_SOURCE" "$APP_CONTENTS/Resources/WeekflowIcon.icns"
touch "$APP_BUNDLE"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Workflow</string>
<key>CFBundleDisplayName</key><string>Workflow</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>WeekflowIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null
fi

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
open_fixture_app() { /usr/bin/open -n "$APP_BUNDLE" --args --development-fixtures; }
package_app() {
  local archive="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.zip"
  local disk_image="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.dmg"
  local image_source
  image_source="$(mktemp -d)"
  mkdir -p "$RELEASE_DIR"
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
  rm -f "$archive"
  rm -f "$disk_image"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$archive"
  /usr/bin/ditto "$APP_BUNDLE" "$image_source/$APP_NAME.app"
  ln -s /Applications "$image_source/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$image_source" \
    -format UDZO \
    -ov \
    "$disk_image" >/dev/null
  rm -rf "$image_source"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  /usr/bin/hdiutil verify "$disk_image" >/dev/null
  echo "$archive"
  echo "$disk_image"
}

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --fixtures|fixtures) open_fixture_app ;;
  --verify-fixtures|verify-fixtures) open_fixture_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --refresh-icon|refresh-icon) /usr/bin/killall Dock; open_app ;;
  --package|package) package_app ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--fixtures|--verify-fixtures|--refresh-icon|--package]" >&2; exit 2 ;;
esac
