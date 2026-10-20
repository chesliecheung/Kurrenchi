#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_PATH="$ROOT_DIR/outputs/Kurrenchi.app"
BACKGROUND_BASE="$ROOT_DIR/Resources/DMGBackground-Base.png"
BACKGROUND_RENDERED="$ROOT_DIR/Resources/DMGBackground.png"
OUTPUT_DMG="$ROOT_DIR/outputs/Kurrenchi-0.5.0-macOS-arm64.dmg"
VOLUME_NAME="Kurrenchi Installer"
SIGN_IDENTITY="${KURRENCHI_SIGN_IDENTITY:--}"

if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "Missing $APP_PATH. Run scripts/package-app.sh first."
    exit 1
fi

if [[ ! -f "$BACKGROUND_BASE" ]]; then
    print -u2 "Missing $BACKGROUND_BASE"
    exit 1
fi

# Avoid Finder writing layout metadata to a previously mounted release.
/usr/bin/hdiutil detach "/Volumes/$VOLUME_NAME" -quiet 2>/dev/null || true

/usr/bin/swift "$ROOT_DIR/scripts/render-dmg-background.swift" "$BACKGROUND_BASE" "$BACKGROUND_RENDERED"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kurrenchi-dmg.XXXXXX")"
RW_DMG="$STAGING_DIR/Kurrenchi-rw.dmg"
MOUNT_DIR=""
mkdir -p "$STAGING_DIR/root/.background"

cleanup() {
    if [[ -n "$MOUNT_DIR" ]]; then
        /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    fi
}
trap cleanup EXIT

/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/root/Kurrenchi.app"
ln -s /Applications "$STAGING_DIR/root/Applications"
/usr/bin/ditto "$BACKGROUND_RENDERED" "$STAGING_DIR/root/.background/background.png"

/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR/root" \
    -format UDRW \
    -fs HFS+ \
    -ov \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT=$(/usr/bin/hdiutil attach "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen)
MOUNT_DIR=$(print -r -- "$ATTACH_OUTPUT" | /usr/bin/sed -n 's#^.*\t\(/Volumes/.*\)$#\1#p' | /usr/bin/tail -1)
if [[ -z "$MOUNT_DIR" ]]; then
    print -u2 "Unable to determine DMG mount path."
    exit 1
fi

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {160, 120, 1060, 680}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Kurrenchi.app" of container window to {220, 300}
        set position of item "Applications" of container window to {680, 300}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
/usr/bin/hdiutil detach "$MOUNT_DIR" -quiet
/usr/bin/hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$OUTPUT_DMG" >/dev/null

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
fi

print "$OUTPUT_DMG"
