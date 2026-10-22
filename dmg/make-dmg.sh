#!/bin/zsh
# Builds JitterBreak.dmg with the layout of the v1.1 DMG: background, app on the left, Applications link on the right.
# Usage: dmg/make-dmg.sh /path/to/JitterBreak.app   (writes JitterBreak.dmg next to this repo)
set -euo pipefail

APP=${1:?usage: make-dmg.sh /path/to/JitterBreak.app}
HERE=${0:A:h}
OUT=${HERE:h:h}/JitterBreak.dmg
VOL=JitterBreak

# Finder addresses the disk by name, so a mounted JitterBreak volume would get the layout instead
[[ -e /Volumes/$VOL ]] && { echo "Eject /Volumes/$VOL first" >&2; exit 1; }

STAGE=$(mktemp -d)
RW=$(mktemp -u).dmg
trap 'rm -rf "$STAGE" "$RW"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$HERE/background.png" "$STAGE/.background/background.png"

# shortcut: hdiutil create warns it's deprecated on macOS 26 but still works; move to 'diskutil image create' when it stops
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 10 ))m
hdiutil create -quiet -volname $VOL -srcfolder "$STAGE" -fs HFS+ -format UDRW -size $SIZE -ov "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')

# Same values as the v1.1 .DS_Store: 733x550 window, 140px icons, 16pt labels, icons at (220,260) and (500,260)
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 933, 670}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 140
    set text size of opts to 16
    set background picture of opts to file ".background:background.png"
    set position of item "JitterBreak.app" to {220, 260}
    set position of item "Applications" to {500, 260}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach -quiet "$DEV"
hdiutil convert -quiet "$RW" -format UDZO -ov -o "$OUT"

# Self-check: the final image has the app, the Applications link and the background
MNT=$(hdiutil attach -readonly -nobrowse -noautoopen "$OUT" | awk -F'\t' '/Apple_HFS/ {print $NF}')
ok=0
[[ -d "$MNT/JitterBreak.app" && -L "$MNT/Applications" && -f "$MNT/.background/background.png" ]] && ok=1
hdiutil detach -quiet "$MNT"
(( ok )) || { echo "DMG check failed: $OUT is missing the app, the Applications link or the background" >&2; exit 1; }

echo "$OUT"
shasum -a 256 "$OUT"
