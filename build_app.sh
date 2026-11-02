#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Building BidiTerm (Release)..."
swift build -c release

APP_NAME="BidiTerm.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$DIR/.build/release/BidiTerm" "$MACOS_DIR/BidiTerm"
chmod +x "$MACOS_DIR/BidiTerm"

# Copy Info.plist
cp "$DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Code sign ad-hoc
echo "==> Code signing BidiTerm.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done! App bundle created at: $APP_DIR"
echo "You can launch it with: open $APP_DIR"
