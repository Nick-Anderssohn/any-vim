#!/usr/bin/env bash
# create-dmg.sh — Package AnyVim.app into a drag-to-Applications .dmg
#
# Usage: create-dmg.sh <path-to-AnyVim.app> <output.dmg>
#
# Arguments:
#   $1  Path to the signed and notarized AnyVim.app bundle
#   $2  Output path for the .dmg file
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <path-to-AnyVim.app> <output.dmg>}"
DMG_PATH="${2:?Usage: create-dmg.sh <path-to-AnyVim.app> <output.dmg>}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: App bundle not found: $APP_PATH" >&2
    exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
STAGING_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "Staging DMG contents in $STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
    -volname "AnyVim" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "DMG created: $DMG_PATH"
