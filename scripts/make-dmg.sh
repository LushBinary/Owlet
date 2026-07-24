#!/usr/bin/env bash
#
# make-dmg.sh — package a built .app into a distributable .dmg
#
# Usage:
#   scripts/make-dmg.sh <path-to-.app> <output.dmg> [volume-name]
#
# Creates a compressed DMG containing the app and a symlink to /Applications
# so users can drag-and-drop to install. No external tooling required (uses
# the built-in hdiutil).

set -euo pipefail

APP_PATH="${1:?Usage: make-dmg.sh <app> <output.dmg> [volume-name]}"
DMG_PATH="${2:?Usage: make-dmg.sh <app> <output.dmg> [volume-name]}"
VOL_NAME="${3:-$(basename "${APP_PATH%.app}")}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found at $APP_PATH" >&2
  exit 1
fi

# Stage the DMG contents in a temp directory.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "Staging $APP_PATH ..."
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Remove any previous artifact.
rm -f "$DMG_PATH"

echo "Building DMG at $DMG_PATH ..."
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
