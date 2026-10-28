# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# One-time setup: creates a persistent self-signed code-signing identity so macOS
# TCC permissions (Accessibility, Input Monitoring) survive rebuilds.
./setup_deps.sh

# Build release bundle (.build/KyroVoice.app) — clears stale Clang module caches automatically.
./build.sh

# Build + kill any running instance + launch the new bundle.
./run.sh

# Makefile aliases
make build   # → ./build.sh
make run     # → ./run.sh
make install # build, copy to /Applications, relaunch from there
make clean   # removes .build/
```

On Command Line Tools for macOS 27 (no Xcode), the default build fails: that SDK's `@State` is a macro whose plugin only ships with Xcode. `build.sh` then retries with the newest macOS 26 SDK and `--build-system native`.

Build target is `arm64` release only (`swift build -c release --arch arm64`). There is no debug scheme, no test suite, and no CI.

Rick runs `/Applications/KyroVoice.app`, so use `make install`, not `make run`, when a fix needs to reach him.

## Architecture

KyroVoice is a **macOS menu-bar app** (no main window) that performs local-on-device voice dictation via NVIDIA Parakeet TDT (CoreML, Apple Neural Engine) and injects transcribed text into the focused app.

`KyroVoiceObjC` exists only so `KVAudioEngineHelper` can wrap `AVAudioEngine` start in `@try`/`@catch`: Swift cannot catch ObjC exceptions.

FluidAudio's default `NemoTextProcessing` trait (a prebuilt Rust text normalizer for TTS) is disabled with `traits: []`, which needs swift-tools-version 6.1; `swiftLanguageModes: [.v5]` keeps the Swift 5 concurrency checks.

Default text injection is synthetic Unicode typing, so the clipboard is never touched. Pasteboard+⌘V is the escape hatch for apps that read the virtual key code instead of the Unicode string; AX insertion works in Cocoa apps but is unreliable in Electron/web.

### Code-signing & TCC

`./setup_deps.sh` creates a self-signed certificate in a dedicated keychain (`~/Library/Keychains/kyro-build.keychain-db`). The build signs the bundle with this identity so macOS keeps TCC grants across rebuilds. Without this setup, permissions must be re-granted after every build. The app is **not sandboxed** (`com.apple.security.app-sandbox = false`).

### Speech model

Parakeet emits punctuation, capitalization and inverse text normalization itself ("nine thirty" -> "9.30"), so `TextProcessor` receives already-formatted text.

### Self-checks

There is no test target. Two runnable checks live behind CLI flags:

```bash
./.build/release/KyroVoice --self-check     # instant, offline: TextProcessor rules
./.build/release/KyroVoice --speech-check   # end-to-end: `say` -> SpeechEngine -> TextProcessor
./.build/release/KyroVoice --overlay-check  # HUD phase -> panel visibility

# Mic cue timing, pre-roll and device switching. --audible plays speech out loud
# through the real coordinator. Quit the installed app first: its open mic
# hides the power-up silence the cue check measures.
open -n -W --stdout /tmp/capture.out --stderr /tmp/capture.out \
    -a .build/KyroVoice.app --args --capture-check [--audible]; cat /tmp/capture.out

# --typing-check posts real key events, so it needs the bundle's Accessibility
# grant: run it through LaunchServices, not from the terminal binary.
open -n -W --stdout /tmp/typing.out --stderr /tmp/typing.out \
    -a /Applications/KyroVoice.app --args --typing-check; cat /tmp/typing.out
```

`--speech-check` synthesises speech with `say -v Alex`, runs it through the real
model, and asserts the final injected text. First run downloads the model.

### Docs site screenshots

```bash
./.build/release/KyroVoice --snapshot docs/img   # re-render the PNGs, then exit
```

`UISnapshot` hosts the real SwiftUI views in a window and draws them into a
bitmap with `displayIgnoringOpacity`, at 2x and in dark appearance. It needs no
Screen Recording grant, unlike `screencapture`. The history window is rendered
from `HistoryStore(sample:)` so the real `history.json` is never touched or
published. The AppKit menu bar dropdown cannot be captured this way; menus are
drawn by the window server.
