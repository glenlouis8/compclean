#!/bin/bash
# Builds CompClean.app in the project folder.
set -euo pipefail
cd "$(dirname "$0")/.."

# Use Xcode's toolchain if installed, without needing xcode-select.
if [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --product CompClean
BIN="$(swift build -c release --show-bin-path)/CompClean"

APP=CompClean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CompClean"

# Liquid Glass icon (Resources/AppIcon.icon, made with icon-composer-mcp from scripts/icon_glyphs.py).
# actool writes Assets.car for macOS 26+ plus an AppIcon.icns fallback.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist .build/icon-partial.plist >/dev/null

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CompClean</string>
  <key>CFBundleDisplayName</key><string>CompClean</string>
  <key>CFBundleIdentifier</key><string>com.glenlouis.compclean</string>
  <key>CFBundleExecutable</key><string>CompClean</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
