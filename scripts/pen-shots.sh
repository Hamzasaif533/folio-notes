#!/bin/bash
# Boots an iPad simulator, runs Folio in demo mode and saves screenshots of the
# fountain pen test page, the pen picker, the PDF test notebook and Settings to ./shots.
set -u
APP="build-sim/Build/Products/Release-iphonesimulator/Folio.app"
BUNDLE="com.personal.folio"
mkdir -p shots

DEVICE=$(xcrun simctl list devices available | grep -E "iPad Pro 13-inch" | tail -1 | grep -oE "[0-9A-F-]{36}")
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun simctl list devices available | grep -E "iPad" | tail -1 | grep -oE "[0-9A-F-]{36}")
fi
echo "Using simulator $DEVICE"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl ui "$DEVICE" appearance light

shot() {
  local name=$1; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" -FolioDemo "$@"
  sleep ${SHOT_WAIT:-8}
  xcrun simctl io "$DEVICE" screenshot "shots/$name.png"
  echo "saved $name"
}

shot "01-library"
shot "02-pen-test" -FolioPenTest
shot "03-pen-picker-middle" -FolioPenTest -FolioFountain -FolioShowPen
shot "04-pen-picker-round" -FolioPenTest -FolioFountain -FolioTipRound -FolioShowPen
shot "05-pen-picker-flat" -FolioPenTest -FolioFountain -FolioTipFlat -FolioShowPen
shot "06-lecture-notes" -FolioOpenFirst
shot "07-pdf-test" -FolioPDFTest
shot "08-settings" -FolioSettings
shot "10-features" -FolioFeatures
shot "11-pdf-dark" -FolioPDFTest -FolioDarkPDF
shot "12-calculator" -FolioOpenFirst -FolioCalc
SHOT_WAIT=25 shot "13-browser" -FolioOpenFirst -FolioBrowser
shot "14-paper-sheet" -FolioFeatures -FolioPaper

# Files that come with the app: a small made-up course put inside the installed app.
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" app)
COURSE="$CONTAINER/BundledFiles/Test Course"
mkdir -p "$COURSE/Week 1" "$COURSE/Week 2"
sips -s format pdf shots/01-library.png --out "$COURSE/Week 1/Lecture 1 Slides.pdf" >/dev/null
printf '<h1>Lab Sheet 2</h1><p>Measure the voltage across each resistor and fill in the table.</p>' > /tmp/lab.html
textutil -convert docx /tmp/lab.html -output "$COURSE/Week 2/Lab Sheet 2.docx"
ls -R "$CONTAINER/BundledFiles"
SHOT_WAIT=12 shot "15-bundled-course" -FolioShowFolder "Test Course"
SHOT_WAIT=12 shot "16-bundled-week2" -FolioShowFolder "Week 2"
SHOT_WAIT=12 shot "17-bundled-pdf" -FolioOpenTitle "Lecture 1 Slides"
shot "18-new-menu" -FolioShowNew
xcrun simctl ui "$DEVICE" appearance dark
shot "09-pen-test-dark" -FolioPenTest
ls -la shots
