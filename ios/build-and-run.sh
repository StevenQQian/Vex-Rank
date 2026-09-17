#!/bin/bash
# Builds the simulator app without an Xcode project: compile VEXRankKit as a
# module, compile the app against it, assemble a .app bundle, install, launch.
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TARGET=arm64-apple-ios17.0-simulator
BUILD=.build/sim
APP="$BUILD/VEXRank.app"
BUNDLE_ID=com.vexrank.app

rm -rf "$BUILD"; mkdir -p "$APP"

echo "==> VEXRankKit"
swiftc -sdk "$SDK" -target "$TARGET" \
  -module-name VEXRankKit -emit-module -emit-module-path "$BUILD/VEXRankKit.swiftmodule" \
  -emit-library -static -o "$BUILD/libVEXRankKit.a" \
  VEXRankKit/Sources/VEXRankKit/*.swift

echo "==> app"
swiftc -sdk "$SDK" -target "$TARGET" -parse-as-library \
  -I "$BUILD" -L "$BUILD" -lVEXRankKit \
  -o "$APP/VEXRank" App/*.swift

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>VEXRank</string>
  <key>CFBundleDisplayName</key><string>VEXRank</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>VEXRank</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST

echo "==> install + launch"
xcrun simctl install booted "$APP"
xcrun simctl launch --console-pty booted "$BUNDLE_ID" 2>/dev/null &
sleep 2
echo "launched $BUNDLE_ID"
