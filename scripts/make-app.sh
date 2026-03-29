#!/bin/bash
# Creates VoiceFlow.app from the swift build output and ad-hoc signs it.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_DIR="$PROJECT_DIR/VoiceFlow.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building VoiceFlow..."
cd "$PROJECT_DIR"
swift build

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable and Info.plist
cp "$BUILD_DIR/VoiceFlow" "$MACOS/VoiceFlow"
cp "$PROJECT_DIR/Sources/VoiceFlow/Resources/Info.plist" "$CONTENTS/Info.plist"
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Ad-hoc sign the bundle so macOS gives it a stable identity for Accessibility.
# "-" means ad-hoc (no Developer ID required). --deep signs nested binaries too.
echo "Signing app bundle..."
codesign --force --deep --sign - \
  --entitlements "$PROJECT_DIR/VoiceFlow.entitlements" \
  "$APP_DIR"

echo ""
echo "✓ Built and signed: $APP_DIR"
echo ""
echo "To run:  open '$APP_DIR'"
echo ""
echo "IMPORTANT — first-run setup:"
echo "  1. Open System Settings → Privacy & Security → Accessibility"
echo "  2. Remove any old VoiceFlow entry, then add VoiceFlow.app again"
echo "  3. Toggle it ON, then relaunch the app"
echo "  After this one-time setup you won't be prompted again."
