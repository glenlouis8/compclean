#!/bin/bash
# Builds Suds.app and packs it into build/Suds-<version>.dmg
# with an Applications shortcut, ready to attach to a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Suds.app/Contents/Info.plist)
STAGE=build/dmg
DMG="build/Suds-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R Suds.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Suds $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
