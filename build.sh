#!/bin/bash
# Build and package SessionHub as a macOS .app

set -e

echo "Building SessionHub (release)..."
swift build -c release

echo "Packaging .app bundle..."
mkdir -p build/SessionHub.app/Contents/MacOS
mkdir -p build/SessionHub.app/Contents/Resources

cp .build/release/SessionHub build/SessionHub.app/Contents/MacOS/SessionHub
chmod +x build/SessionHub.app/Contents/MacOS/SessionHub

# Info.plist already exists in build/ — no need to regenerate

echo ""
echo "✅ Built: build/SessionHub.app"
echo ""
echo "To install:  cp -r build/SessionHub.app /Applications/"
echo "To launch:   open /Applications/SessionHub.app"
