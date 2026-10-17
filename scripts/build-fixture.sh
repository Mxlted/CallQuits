#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/CallQuits Fixture.app"
mkdir -p "$ROOT/.build/ModuleCache" "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$ROOT/.build/ModuleCache" -framework AppKit \
  "$ROOT/scripts/fixtures/FixtureApp.swift" -o "$APP/Contents/MacOS/CallQuitsFixture"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CallQuitsFixture</string>
<key>CFBundleIdentifier</key><string>app.callquits.Fixture</string>
<key>CFBundleName</key><string>CallQuits Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Launch when ready: open \"$APP\""
