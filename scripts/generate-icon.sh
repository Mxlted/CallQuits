#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/ModuleCache" "$ROOT/build"
swift -module-cache-path "$ROOT/.build/ModuleCache" "$ROOT/scripts/generate-icon.swift" "$ROOT/build/AppIcon.iconset"
iconutil --convert icns "$ROOT/build/AppIcon.iconset" --output "$ROOT/Resources/AppIcon.icns"
cp "$ROOT/build/AppIcon.iconset/icon_512x512.png" "$ROOT/Resources/AppIcon.png"
echo "Generated Resources/AppIcon.icns and Resources/AppIcon.png"
