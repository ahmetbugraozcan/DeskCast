#!/bin/sh
# Builds libDeskCastNowPlaying.dylib into the app's Frameworks folder.
# Run from the "Build Now Playing Adapter" phase of the screenshotapp target.
set -eu

SOURCE="$SRCROOT/NowPlayingAdapter/DeskCastNowPlaying.m"
OUTPUT="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/libDeskCastNowPlaying.dylib"

mkdir -p "$(dirname "$OUTPUT")"

ARCH_FLAGS=""
for ARCH in $ARCHS; do
    ARCH_FLAGS="$ARCH_FLAGS -arch $ARCH"
done

# shellcheck disable=SC2086
xcrun --sdk macosx clang -dynamiclib -fobjc-arc -O2 \
    $ARCH_FLAGS \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -install_name "@rpath/libDeskCastNowPlaying.dylib" \
    -framework Foundation \
    "$SOURCE" -o "$OUTPUT"

# The app's own signature seals this file, so it must be signed first.
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp=none "$OUTPUT"
else
    codesign --force --sign - "$OUTPUT"
fi
