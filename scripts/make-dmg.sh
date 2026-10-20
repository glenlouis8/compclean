#!/bin/bash
# Builds CompClean.app and packs it into build/CompClean-<version>.dmg
# with an Applications shortcut, ready to attach to a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" CompClean.app/Contents/Info.plist)
STAGE=build/dmg
DMG="build/CompClean-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R CompClean.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "CompClean $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
