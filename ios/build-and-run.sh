#!/bin/bash
# Builds the simulator app without an Xcode project: compile VEXRankKit as a
# module, compile the app against it, assemble a .app bundle, install, launch.
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TARGET=arm64-apple-ios17.0-simulator
BUILD=.build/sim
APP="$BUILD/MakapakaScout.app"
BUNDLE_ID=com.vexrank.app

rm -rf "$BUILD"; mkdir -p "$APP"

echo "==> VEXRankKit"
swiftc -O -sdk "$SDK" -target "$TARGET" \
  -module-name VEXRankKit -emit-module -emit-module-path "$BUILD/VEXRankKit.swiftmodule" \
  -emit-library -static -o "$BUILD/libVEXRankKit.a" \
  VEXRankKit/Sources/VEXRankKit/*.swift

echo "==> app"
swiftc -O -sdk "$SDK" -target "$TARGET" -parse-as-library \
  -I "$BUILD" -L "$BUILD" -lVEXRankKit \
  -o "$APP/MakapakaScout" App/*.swift Shared/*.swift

# Tournament mode's Live Activity is drawn by a widget extension, embedded in
# the app's PlugIns. It shares Shared/ with the app, and builds the two
# VEXRankKit files the app's icons are drawn from rather than linking the
# kit - an extension may not link code that is not extension-safe.
echo "==> widget extension"
APPEX="$APP/PlugIns/TournamentWidget.appex"
mkdir -p "$APPEX"
# The entry point is the extension runtime's, as Xcode links it; left to the
# @main bundle's own, the process starts and exits before drawing anything.
swiftc -O -sdk "$SDK" -target "$TARGET" -parse-as-library -application-extension \
  -module-name TournamentWidget -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/TournamentWidget" Widget/*.swift Shared/*.swift \
  VEXRankKit/Sources/VEXRankKit/StrokeIcons.swift VEXRankKit/Sources/VEXRankKit/StrokePath.swift
cat > "$APPEX/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TournamentWidget</string>
  <key>CFBundleDisplayName</key><string>Tournament mode</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.TournamentWidget</string>
  <key>CFBundleExecutable</key><string>TournamentWidget</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
PLIST

# The asset catalog, which swiftc knows nothing about. Without this the
# simulator build shows a blank tile while the Xcode build shows the icon,
# and the difference is easy to mistake for the icon being wrong.
if [ -d App/Assets.xcassets ]; then
  echo "==> icon"
  xcrun actool App/Assets.xcassets \
    --compile "$APP" \
    --platform iphonesimulator --minimum-deployment-target 17.0 \
    --app-icon AppIcon --output-partial-info-plist "$BUILD/icon.plist" \
    --output-format human-readable-text >/dev/null
fi

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Makapaka Scout</string>
  <key>CFBundleDisplayName</key><string>Makapaka Scout</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MakapakaScout</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>17.0</string>
  <!-- Every theme is dark. Left to default, the launch screen is white, so the
       app opens with a white flash and then crossfades into a near-black
       interface - which reads as the app being slow to start. -->
  <key>UILaunchScreen</key><dict><key>UIColorName</key><string>LaunchBackground</string></dict>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <!-- Tournament mode: the Live Activity, and the background refresh that
       keeps it current while the app is closed. -->
  <key>NSSupportsLiveActivities</key><true/>
  <key>UIBackgroundModes</key><array><string>fetch</string></array>
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array><string>$BUNDLE_ID.tournament</string></array>
</dict></plist>
PLIST

echo "==> install + launch"
xcrun simctl install booted "$APP"
xcrun simctl launch --console-pty booted "$BUNDLE_ID" 2>/dev/null &
sleep 2
echo "launched $BUNDLE_ID"
