#!/bin/bash
# build.sh — compile KyroVoice and assemble a runnable .app bundle
set -euo pipefail

cd "$(dirname "$0")"

# Stale Clang module caches break builds after the repo is moved or renamed (absolute paths baked into PCM files).
rm -rf .build/*/release/ModuleCache .build/*/debug/ModuleCache 2>/dev/null || true

APP_NAME="KyroVoice"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="Resources/KyroVoice.entitlements"

echo "==> Building ${APP_NAME} (release, arm64)…"
swift build -c release --arch arm64

echo "==> Assembling ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy any SwiftPM resource bundles (e.g. WhisperKit) into Resources/
for bundle in "$RELEASE_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

echo "==> Done. Built: $APP_BUNDLE"
