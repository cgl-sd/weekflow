#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Weekflow"
RELEASE_BUNDLE_ID="com.weekflow.app"
DEBUG_BUNDLE_ID="com.weekflow.app.debug"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/01_workspace"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
RELEASE_NOTES_SOURCE="$ROOT_DIR/RELEASE_NOTES.md"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_CONFIGURATION="debug"
PACKAGE_TEMP_DIR=""

cleanup() {
  if [[ -n "$PACKAGE_TEMP_DIR" && -d "$PACKAGE_TEMP_DIR" ]]; then
    rm -rf "$PACKAGE_TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

if [[ "$MODE" == "--package" || "$MODE" == "package" || "$MODE" == "--release" || "$MODE" == "release" ]]; then
  BUILD_CONFIGURATION="release"
fi

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  BUNDLE_ID="$RELEASE_BUNDLE_ID"
else
  BUNDLE_ID="$DEBUG_BUNDLE_ID"
fi

resolve_version() {
  if [[ -n "${WEEKFLOW_VERSION:-}" ]]; then
    printf '%s\n' "$WEEKFLOW_VERSION"
    return
  fi
  local exact_tag
  exact_tag="$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true)"
  if [[ "$exact_tag" == v* ]]; then
    printf '%s\n' "${exact_tag#v}"
    return
  fi
  tr -d '[:space:]' < "$VERSION_FILE"
}

APP_VERSION="$(resolve_version)"
BUILD_NUMBER="${WEEKFLOW_BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$PACKAGE_DIR/Resources/WeekflowIcon.icns"
ENTITLEMENTS="$ROOT_DIR/script/Weekflow.entitlements"
CONTAINER_MIGRATION="$ROOT_DIR/script/container-migration.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

run_release_checks() {
  swift test
  swift build -c release
}

validate_formal_release_source() {
  local exact_tag
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]]; then
    printf 'Formal release requires a clean tracked worktree.\n' >&2
    exit 1
  fi
  exact_tag="$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true)"
  if [[ "$exact_tag" != "v$APP_VERSION" ]]; then
    printf 'Formal release requires exact tag v%s (current: %s).\n' "$APP_VERSION" "${exact_tag:-none}" >&2
    exit 1
  fi
}

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  cd "$PACKAGE_DIR"
  run_release_checks
else
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  cd "$PACKAGE_DIR"
  swift build
fi

BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_CONTENTS/Resources/WeekflowIcon.icns"
if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  cp "$CONTAINER_MIGRATION" "$APP_CONTENTS/Resources/container-migration.plist"
fi

/usr/libexec/PlistBuddy -c 'Clear dict' "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string zh_CN' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleLocalizations array' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleLocalizations:0 string zh-Hans' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string WeekflowIcon' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$INFO_PLIST"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Info.plist validation failed: %s expected %s, got %s\n' "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

validate_bundle() {
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
  assert_plist_value CFBundleIdentifier "$BUNDLE_ID"
  assert_plist_value CFBundleName "$APP_NAME"
  assert_plist_value CFBundleDisplayName "$APP_NAME"
  assert_plist_value CFBundleShortVersionString "$APP_VERSION"
  assert_plist_value CFBundleVersion "$BUILD_NUMBER"
  assert_plist_value LSMinimumSystemVersion "$MIN_SYSTEM_VERSION"
}
validate_bundle

verify_bundle_cleanliness() {
  local forbidden
  forbidden="$(find "$APP_BUNDLE" \( -name '.data' -o -name 'Backups' -o -name 'RestoreSafety' -o -name '*.store' -o -name '*.store-wal' -o -name '*.store-shm' -o -name 'backup-status.json' -o -name 'persistence-failure.json' \) -print)"
  if [[ -n "$forbidden" ]]; then
    printf 'Release bundle contains forbidden runtime data:\n%s\n' "$forbidden" >&2
    exit 1
  fi
}
verify_bundle_cleanliness

validate_release_security_inputs() {
  /usr/bin/plutil -lint "$ENTITLEMENTS" "$CONTAINER_MIGRATION" >/dev/null
  local sandbox network user_files migration_source
  sandbox="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")"
  network="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$ENTITLEMENTS")"
  user_files="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$ENTITLEMENTS")"
  migration_source="$(/usr/libexec/PlistBuddy -c 'Print :Move:0' "$CONTAINER_MIGRATION")"
  [[ "$sandbox" == "true" && "$network" == "true" && "$user_files" == "true" ]]
  [[ "$migration_source" == '${ApplicationSupport}/Weekflow' ]]
  [[ -f "$APP_CONTENTS/Resources/container-migration.plist" ]]
}

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  validate_release_security_inputs
fi

# Debug builds read project-local data. Give the reconstructed app bundle a
# stable code-signing identifier so macOS does not treat every rebuild as a
# completely unrelated executable when remembering Files & Folders consent.
if [[ "$BUILD_CONFIGURATION" == "debug" ]]; then
  /usr/bin/codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
fi

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
open_fixture_app() { /usr/bin/open -n "$APP_BUNDLE" --args --development-fixtures; }

create_artifacts() {
  local archive="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.zip"
  local disk_image="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.dmg"
  PACKAGE_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weekflow-package.XXXXXX")"
  mkdir -p "$RELEASE_DIR" "$PACKAGE_TEMP_DIR/image"
  rm -f "$archive" "$disk_image"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$archive"
  /usr/bin/ditto "$APP_BUNDLE" "$PACKAGE_TEMP_DIR/image/$APP_NAME.app"
  ln -s /Applications "$PACKAGE_TEMP_DIR/image/Applications"
  /usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$PACKAGE_TEMP_DIR/image" -format UDZO -ov "$disk_image" >/dev/null
  /usr/bin/hdiutil verify "$disk_image" >/dev/null
  printf '%s\n%s\n' "$archive" "$disk_image"
}

write_release_metadata() {
  local archive="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.zip"
  local disk_image="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.dmg"
  local checksums="$RELEASE_DIR/SHA256SUMS"
  local manifest="$RELEASE_DIR/BUILD-MANIFEST.json"
  local commit swift_version xcode_version
  commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  swift_version="$(swift --version)"
  swift_version="${swift_version%%$'\n'*}"
  xcode_version="$(xcodebuild -version)"
  xcode_version="${xcode_version%%$'\n'*}"
  (cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$(basename "$archive")" "$(basename "$disk_image")" > "$(basename "$checksums")")
  printf '{\n  "schemaVersion": 1,\n  "version": "%s",\n  "build": "%s",\n  "commit": "%s",\n  "minimumMacOS": "%s",\n  "swift": "%s",\n  "xcode": "%s"\n}\n' \
    "$APP_VERSION" "$BUILD_NUMBER" "$commit" "$MIN_SYSTEM_VERSION" "$swift_version" "$xcode_version" > "$manifest"
  chmod 644 "$checksums" "$manifest"
  if [[ -f "$RELEASE_NOTES_SOURCE" ]]; then
    cp "$RELEASE_NOTES_SOURCE" "$RELEASE_DIR/RELEASE_NOTES.md"
  fi
  printf '%s\n%s\n%s\n%s\n' "$archive" "$disk_image" "$checksums" "$manifest"
}

package_preview() {
  /usr/bin/codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  /usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null \
    | /usr/bin/plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - - \
    | /usr/bin/grep -qx true
  create_artifacts
  write_release_metadata
}

package_release() {
  : "${WEEKFLOW_DEVELOPER_ID:?Set WEEKFLOW_DEVELOPER_ID to a Developer ID Application identity}"
  : "${WEEKFLOW_NOTARY_PROFILE:?Set WEEKFLOW_NOTARY_PROFILE to a notarytool keychain profile}"
  validate_formal_release_source
  /usr/bin/codesign --force --deep --strict --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$WEEKFLOW_DEVELOPER_ID" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  PACKAGE_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weekflow-notary.XXXXXX")"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PACKAGE_TEMP_DIR/Weekflow-notary.zip"
  /usr/bin/xcrun notarytool submit "$PACKAGE_TEMP_DIR/Weekflow-notary.zip" \
    --keychain-profile "$WEEKFLOW_NOTARY_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  /usr/sbin/spctl -a -vv "$APP_BUNDLE"
  rm -rf "$PACKAGE_TEMP_DIR"
  PACKAGE_TEMP_DIR=""
  create_artifacts
  local disk_image="$RELEASE_DIR/$APP_NAME-v$APP_VERSION-macOS.dmg"
  /usr/bin/codesign --force --timestamp --sign "$WEEKFLOW_DEVELOPER_ID" "$disk_image"
  /usr/bin/codesign --verify --strict "$disk_image"
  /usr/bin/xcrun notarytool submit "$disk_image" \
    --keychain-profile "$WEEKFLOW_NOTARY_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$disk_image"
  /usr/bin/xcrun stapler validate "$disk_image"
  /usr/bin/hdiutil verify "$disk_image" >/dev/null
  write_release_metadata
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
  --package|package) package_preview ;;
  --release|release) package_release ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--fixtures|--verify-fixtures|--refresh-icon|--package|--release]" >&2; exit 2 ;;
esac
