#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TinyShotShelf"
BUNDLE_ID="com.ahmetbugraozcan.screenshotapp"
PROJECT_NAME="screenshotapp.xcodeproj"
SCHEME_NAME="screenshotapp"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
BUILD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
APP_BINARY_PATH="$DIST_APP_PATH/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS" \
  build

rm -rf "$DIST_APP_PATH"
mkdir -p "$DIST_DIR"
ditto "$BUILD_APP_PATH" "$DIST_APP_PATH"

open_app() {
  /usr/bin/open -n "$DIST_APP_PATH"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY_PATH"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
