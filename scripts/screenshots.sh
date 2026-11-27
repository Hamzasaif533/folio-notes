#!/bin/bash
# Boots an iPad simulator, runs Folio in demo mode and saves screenshots to ./shots.
set -u
APP="build-sim/Build/Products/Release-iphonesimulator/Folio.app"
BUNDLE="com.personal.folio"
mkdir -p shots

DEVICE=$(xcrun simctl list devices available | grep -E "iPad Pro 13-inch" | tail -1 | grep -oE "[0-9A-F-]{36}")
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun simctl list devices available | grep -E "iPad" | tail -1 | grep -oE "[0-9A-F-]{36}")
fi
echo "Using simulator $DEVICE"
xcrun simctl list devices available | grep "$DEVICE"

xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
open -a Simulator --args -CurrentDeviceUDID "$DEVICE" || true
sleep 5
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$DEVICE" "$APP"

shot() {
  local name=$1; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" -FolioDemo "$@"
  sleep 7
  xcrun simctl io "$DEVICE" screenshot "shots/$name.png"
  echo "saved $name"
}

rotate() {
  # Cmd+Right arrow rotates the simulator (needs UI scripting; ignored if unavailable).
  osascript -e 'tell application "Simulator" to activate' \
            -e 'tell application "System Events" to key code 124 using command down' || echo "rotate unavailable"
  sleep 3
}

run_set() {
  local suffix=$1
  shot "01-library-$suffix"
  shot "02-folders-$suffix" -FolioShowFolders
  shot "03-editor-$suffix" -FolioOpenFirst
  shot "04-pen-settings-$suffix" -FolioOpenFirst -FolioShowPen
  shot "05-squeeze-$suffix" -FolioOpenFirst -FolioSqueeze
  shot "06-canvas-$suffix" -FolioOpenCanvas
}

xcrun simctl ui "$DEVICE" appearance light
run_set "portrait-light"
shot "07-new-menu-portrait-light" -FolioShowNew
shot "08-sidebar-portrait-light" -FolioOpenFirst -FolioSidebar
shot "09-dock-left-portrait-light" -FolioOpenFirst -FolioDockLeft
shot "10-focus-portrait-light" -FolioOpenFirst -FolioFocus
xcrun simctl ui "$DEVICE" appearance dark
run_set "portrait-dark"

rotate
xcrun simctl ui "$DEVICE" appearance dark
shot "01-library-landscape-dark"
shot "03-editor-landscape-dark" -FolioOpenFirst
xcrun simctl ui "$DEVICE" appearance light
shot "02-folders-landscape-light" -FolioShowFolders
shot "03-editor-landscape-light" -FolioOpenFirst -FolioDockBottom

ls -la shots
