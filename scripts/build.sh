#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/.build"
APP="$ROOT/build/CallQuits.app"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "CONFIGURATION must be debug or release." >&2; exit 1 ;;
esac

mkdir -p "$BUILD_ROOT/cache" "$BUILD_ROOT/config" "$BUILD_ROOT/security" "$BUILD_ROOT/ModuleCache" "$ROOT/build"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/ModuleCache"
export MACOSX_DEPLOYMENT_TARGET=14.0

SWIFT_FLAGS=(--package-path "$ROOT" --scratch-path "$BUILD_ROOT/swiftpm" --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --disable-sandbox --configuration "$CONFIGURATION")
swift build "${SWIFT_FLAGS[@]}" --product CallQuits
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

# Preserve the bundle directory identity so Finder/open panels do not retain stale file references.
# Replace only generated contents, never an installed application.
rm -rf "$APP/Contents"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CallQuits" "$APP/Contents/MacOS/CallQuits"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo "Signing identity: $SIGN_IDENTITY (a dash means local ad hoc signing)"
