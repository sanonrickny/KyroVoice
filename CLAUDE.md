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
make clean   # removes .build/
```

Build target is `arm64` release only (`swift build -c release --arch arm64`). There is no debug scheme, no test suite, and no CI.

### Web UI (design prototype only — not wired to the app)
```bash
cd web && npm run dev    # Vite dev server
cd web && npm run build  # production build to web/dist/
```

The React app in `web/` is a standalone visual prototype of the settings UI. It is not loaded by the macOS app at runtime.

## Architecture

KyroVoice is a **macOS menu-bar app** (no main window) that performs local-on-device voice dictation via WhisperKit and injects transcribed text into the focused app.

### Dependency graph (wired in `AppDelegate.applicationDidFinishLaunching`)

```
HotkeyManager ──down/up──▶ DictationCoordinator
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        AudioRecorder        WhisperEngine         TextProcessor
         (AVAudioEngine)      (WhisperKit actor)   (rule pipeline)
                                                        │
                                                        ▼
                                               ClipboardInjector
                                           (pasteboard+⌘V or AX)
              ┌──────────────────────────────────────────┘
              ▼
        ModeResolver        OverlayState ◀── FloatingOverlay (NSPanel)
      (frontmost app BID)
```

`DictationCoordinator` is the central pipeline: hotkey-down starts recording, hotkey-up stops and kicks off `whisper → processor → injector`. Everything is `@MainActor` except `WhisperEngine` (a Swift `actor`).

### Key types

| Type | File | Role |
|---|---|---|
| `DictationCoordinator` | `Core/DictationCoordinator.swift` | Pipeline orchestrator |
| `AudioRecorder` | `Core/AudioRecorder.swift` | AVAudioEngine tap → 16 kHz Float32 PCM |
| `WhisperEngine` | `Core/Whisper/WhisperEngine.swift` | Swift actor wrapping WhisperKit |
| `TextProcessor` | `Core/TextProcessor.swift` | Mode-gated rule pipeline (offline) |
| `ClipboardInjector` | `Services/ClipboardInjector.swift` | Pasteboard+⌘V or AX text insertion |
| `ModeResolver` | `Services/ModeResolver.swift` | Maps frontmost app bundle ID → `DictationMode` |
| `HotkeyManager` | `Services/HotkeyManager.swift` | Carbon `RegisterEventHotKey` (press + release) |
| `SettingsStore` | `Settings/SettingsStore.swift` | `@MainActor` singleton backed by `UserDefaults` |
| `FloatingOverlay` | `UI/FloatingOverlay.swift` | Borderless `NSPanel` with SwiftUI waveform HUD |
| `MenuBarController` | `UI/MenuBarController.swift` | `NSStatusItem` + `NSMenu` |
| `OverlayState` | `UI/OverlayState.swift` | Observable phase enum: hidden/listening/processing/injected/error |

### Swift package targets

- **`KyroVoice`** — main executable (`Sources/KyroVoice/`)
- **`KyroVoiceObjC`** — thin Objective-C shim (`Sources/KyroVoiceObjC/`) providing `KVAudioEngineHelper` to safely wrap `AVAudioEngine` start in an ObjC `@try`/`@catch` block (Swift cannot catch ObjC exceptions).

Dependency: `WhisperKit` from `https://github.com/argmaxinc/WhisperKit` (≥ 0.9.0).

### Dictation modes & text processing

`DictationMode` has three values (`normal`, `email`, `code`). `ModeResolver` selects the mode automatically from the frontmost app's bundle ID (VS Code, Xcode, iTerm → `.code`; Mail, Outlook → `.email`; otherwise the user's default). `TextProcessor` runs a deterministic rule pipeline per mode:

- **normal**: unicode normalization → whitespace normalization → filler stripping → punctuation spacing → sentence capitalization
- **email**: normal + contraction expansion + small number spelling
- **code**: unicode + whitespace + spoken-syntax expansion (`"open paren"` → `(`) + case conversion (`"camel case foo bar"` → `fooBar`) + symbol spacing

### Text injection strategies (`InjectionStrategyKind`)

- **pasteboard** (default): snapshots the current pasteboard, writes text, posts synthetic ⌘V, then restores the original pasteboard after 200 ms.
- **accessibility**: uses `AXUIElementSetAttributeValue(kAXSelectedTextAttribute)` — works in Cocoa apps, unreliable in Electron/web.
- **auto**: tries AX, falls back to pasteboard on error.

### Permissions required

Microphone, Accessibility, and Input Monitoring. `PermissionsService` (`@MainActor`) probes and requests each. Accessibility is needed for `ClipboardInjector.axInject`; Input Monitoring is needed to post synthetic `CGEvent` key presses.

### Hotkey configuration

Hardcoded default is ⌘⇧Space (`HotkeyConfig.default`). To change it, edit `Sources/KyroVoice/Models/HotkeyConfig.swift` and rebuild. The `HotkeyMode` enum supports `pushToTalk` (hold) and `toggle` (tap).

### Code-signing & TCC

`./setup_deps.sh` creates a self-signed certificate in a dedicated keychain (`~/Library/Keychains/kyro-build.keychain-db`). The build signs the bundle with this identity so macOS keeps TCC grants across rebuilds. Without this setup, permissions must be re-granted after every build. The app is **not sandboxed** (`com.apple.security.app-sandbox = false`).

### Whisper model storage

Models are downloaded by WhisperKit on first use into `~/Library/Application Support/KyroVoice/Models`. Available variants: `base.en` (≈75 MB) and `small.en` (≈250 MB, default).
