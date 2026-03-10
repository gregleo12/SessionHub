#!/bin/bash
# Build, package, and sign SessionHub as a macOS .app

set -e

echo "Building SessionHub (release)..."
swift build -c release

echo "Packaging .app bundle..."
APP=build/SessionHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/SessionHub "$APP/Contents/MacOS/SessionHub"
chmod +x "$APP/Contents/MacOS/SessionHub"
cp Info.plist "$APP/Contents/Info.plist"

# Sign with ad-hoc or Apple Development identity
# No special entitlements needed — uses WebSocket (no Apple Events/TCC)
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk -F'"' '{print $2}')
if [ -z "$IDENTITY" ]; then
    echo ""
    echo "Signing with ad-hoc identity..."
    codesign --force --deep --sign - "$APP"
else
    echo "Signing with: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" \
        --entitlements entitlements.plist \
        "$APP"
fi

echo ""
echo "✅ Built: $APP"
echo ""
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Authority|Info.plist" || true
echo ""
echo "To launch:   open $APP"
echo ""
echo "NOTE: Enable iTerm2 Python API first:"
echo "  iTerm2 → Settings → General → Magic → Enable Python API"
