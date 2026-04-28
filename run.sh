#!/bin/bash
# run.sh — kill any prior instance and launch the freshly built bundle
set -euo pipefail

cd "$(dirname "$0")"

APP_BUNDLE=".build/KyroVoice.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Bundle not found. Running ./build.sh first…"
    ./build.sh
fi

if pgrep -x KyroVoice >/dev/null; then
    echo "==> Killing existing KyroVoice instance…"
    pkill -x KyroVoice 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x KyroVoice >/dev/null || break
        sleep 0.2
    done
    if pgrep -x KyroVoice >/dev/null; then
        echo "==> Force-killing stubborn instance…"
        pkill -9 -x KyroVoice 2>/dev/null || true
        sleep 0.3
    fi
fi

open -n "$APP_BUNDLE"
echo "==> KyroVoice launched. Look for the mic icon in your menu bar."
