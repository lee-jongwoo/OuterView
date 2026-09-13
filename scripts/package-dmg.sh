#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/OuterView.app}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUTPUT="$ROOT/dist/OuterView-$VERSION.dmg"

# Verify the exported app before copying it, preserving its signature and ticket.
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
mkdir -p "$ROOT/dist"
if [[ -e "$OUTPUT" ]]; then
  echo "Already exists: $OUTPUT (move it aside before rebuilding)" >&2
  exit 1
fi
STAGING=$(mktemp -d /private/tmp/outerview-dmg.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/OuterView.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname OuterView -srcfolder "$STAGING" -format UDZO "$OUTPUT"
hdiutil verify "$OUTPUT"
echo "Created: $OUTPUT"
echo 'If signing/notarizing the DMG, do so before generating its final checksum.'
