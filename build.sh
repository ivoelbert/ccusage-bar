#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="CCUsageBar"
DISPLAY_NAME="CCUsage Bar"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/${DISPLAY_NAME}.app"
BIN_PATH="$BUILD_DIR/$APP_NAME"

mkdir -p "$BUILD_DIR"

echo "==> Compiling Swift sources..."
xcrun swiftc \
    -O \
    -target arm64-apple-macos14 \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library \
    -o "$BIN_PATH" \
    Sources/CCUsageBar/CCUsageBarApp.swift \
    Sources/CCUsageBar/CCUsageModel.swift \
    Sources/CCUsageBar/Messages.swift \
    Sources/CCUsageBar/PopoverView.swift

echo "==> Assembling .app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Done. App bundle: $APP_BUNDLE"
echo ""
echo "To run:     open \"$APP_BUNDLE\""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
