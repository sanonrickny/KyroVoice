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
# ponytail: the Command Line Tools for macOS 27 ship an SDK whose @State is a
# macro, but not the SwiftUIMacros plugin (that comes with Xcode), and the new
# build system cannot parse that SDK at all. Fall back to the newest older SDK.
# Drop this once Xcode is installed or the CLT ships the plugin.
if ! swift build -c release --arch arm64; then
    FALLBACK_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk 2>/dev/null | sort -V | tail -1)
    [ -n "$FALLBACK_SDK" ] || exit 1
    echo "==> Retrying with $FALLBACK_SDK"
    SDKROOT="$FALLBACK_SDK" swift build -c release --arch arm64 --build-system native
fi

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

# Use a persistent self-signed identity if available (keeps TCC grants
# across rebuilds). Fall back to ad-hoc signing with a warning.
IDENTITY="KyroVoice Dev"
BUILD_KC="$HOME/Library/Keychains/kyro-build.keychain-db"
KC_PASS="kyro-build-pass"

if [ -f "$BUILD_KC" ]; then
    security unlock-keychain -p "$KC_PASS" "$BUILD_KC" 2>/dev/null || true
fi

IDENTITY_HASH=$(security find-identity -v -p codesigning "$BUILD_KC" 2>/dev/null | grep "$IDENTITY" | head -1 | awk '{print $2}')
if [ -f "$BUILD_KC" ] && [ -n "$IDENTITY_HASH" ]; then
    codesign --force --deep --sign "$IDENTITY_HASH" \
        --keychain "$BUILD_KC" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE"
else
    echo "    WARNING: No persistent '$IDENTITY' identity found."
    echo "    Run ./setup_deps.sh once to create one."
    echo "    Until then, TCC permissions (Accessibility/Input Monitoring)"
    echo "    will be lost on every rebuild."
    codesign --force --deep --sign - \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE"
fi

echo "==> Done. Built: $APP_BUNDLE"
