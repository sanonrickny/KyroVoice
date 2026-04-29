# AGENTS.md

## Build & Run
- **Main App (Swift/macOS)**:
  - Build: `./build.sh` (compiles for arm64, assembles `.app` bundle, and ad-hoc codesigns)
  - Run: `./run.sh` (kills existing instances and launches `.build/KyroVoice.app`)
  - Note: Stale Clang module caches are cleared automatically in `build.sh` to prevent path-related build failures.
- **Settings UI (React/Vite)**:
  - Directory: `/web`
  - Dev: `cd web && npm run dev`
  - Build: `cd web && npm run build`

## Architecture
- **Core**: Local-first voice dictation for macOS using Whisper on Apple Silicon.
- **Frontend**: A React-based settings interface located in `/web`.
- **Resources**: App entitlements and plist are in `/Resources`.

## Constraints & Quirks
- **Hardware**: Requires Apple Silicon (M1/M2/M3) and macOS 13+.
- **Toolchain**: Requires Xcode 15+.
- **Bundle**: The final executable is an Apple `.app` bundle located in `.build/KyroVoice.app`.
