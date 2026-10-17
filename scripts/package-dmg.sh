#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP_BUNDLE_PATH:-$ROOT/build/CallQuits.app}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

case "$SIGN_IDENTITY" in
  'Developer ID Application: '*) ;;
  *) echo "Set CODE_SIGN_IDENTITY to your Developer ID Application identity." >&2; exit 1 ;;
esac

if ! APP="$(cd -P -- "$APP" && pwd -P)"; then
  echo "The source app must be an existing directory." >&2
  exit 1
fi
if [[ ! -x "$APP/Contents/MacOS/CallQuits" ]]; then
  echo "A built CallQuits.app is required: $APP" >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" != 'app.callquits.CallQuits' ]]; then
  echo "The source bundle is not CallQuits." >&2
  exit 1
fi

RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_ARCHS="$(lipo -archs "$APP/Contents/MacOS/CallQuits" | tr ' ' '-')"
case "$RELEASE_VERSION" in
  ''|*[!0-9A-Za-z._-]*) echo "The bundle version cannot be used in a release filename." >&2; exit 1 ;;
esac
OUTPUT="${DMG_OUTPUT_PATH:-$ROOT/build/CallQuits-${RELEASE_VERSION}-macos-${RELEASE_ARCHS}.dmg}"
case "$OUTPUT" in
  *.dmg) ;;
  *) echo "DMG_OUTPUT_PATH must end in .dmg." >&2; exit 1 ;;
esac

# Resolve symlinks before creating anything: staging inside the source bundle
# would change its signature and recursively copy the staging directory.
if ! OUTPUT_PARENT="$(cd -P -- "$(dirname "$OUTPUT")" && pwd -P)"; then
  echo "The DMG output parent directory must already exist." >&2
  exit 1
fi
if [[ "$OUTPUT_PARENT" == "$APP" || "$OUTPUT_PARENT" == "$APP/"* ]]; then
  echo "The DMG output must be outside the source app bundle." >&2
  exit 1
fi
OUTPUT="$OUTPUT_PARENT/$(basename "$OUTPUT")"
if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
  echo "Refusing to replace an existing artifact: $OUTPUT" >&2
  exit 1
fi

# Packaging never rebuilds, re-signs, or modifies the finalized source app.
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
WORK_DIR="$(mktemp -d "$OUTPUT_PARENT/.dmg-package.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir "$WORK_DIR/contents"
ditto "$APP" "$WORK_DIR/contents/CallQuits.app"
ln -s /Applications "$WORK_DIR/contents/Applications"
codesign --verify --deep --strict "$WORK_DIR/contents/CallQuits.app"
xcrun stapler validate "$WORK_DIR/contents/CallQuits.app"

hdiutil create -volname CallQuits -fs HFS+ -format UDZO \
  -srcfolder "$WORK_DIR/contents" "$WORK_DIR/CallQuits.dmg"
codesign --sign "$SIGN_IDENTITY" --timestamp "$WORK_DIR/CallQuits.dmg"
codesign --verify --strict "$WORK_DIR/CallQuits.dmg"
hdiutil verify "$WORK_DIR/CallQuits.dmg"

# A hard link publishes the finished bytes atomically without clobbering a
# destination created by another process while packaging was in progress.
/bin/link "$WORK_DIR/CallQuits.dmg" "$OUTPUT"
echo "Created $OUTPUT"
echo "Submit this DMG for notarization, staple it, then create its checksum."
