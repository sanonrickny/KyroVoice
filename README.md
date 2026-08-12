# KyroVoice 🎙️

Local-first voice dictation for macOS. Powered by NVIDIA Parakeet TDT running
on the Apple Neural Engine.

**[Site: sanonrickny.github.io/KyroVoice](https://sanonrickny.github.io/KyroVoice/)** — pipeline, models, and modes.

## ✨ Features
- **100% Private**: All processing happens on-device.
- **Smart Modes**: Normal, Email, and Code-optimized dictation.
- **Seamless**: Hold a hotkey, speak, and text appears at your cursor.

## 🚀 Quick Start

### Requirements
- macOS 14+ (Apple Silicon)
- Xcode 15+

### Build & Run
```bash
./setup_deps.sh   # once: persistent signing identity so TCC grants survive rebuilds
make install      # build, install to /Applications, relaunch
```

`make run` builds and launches from `.build/` instead, without installing.

## 🛠️ Usage
- **Hotkey**: `⌘ ⇧ Space` (Hold to talk)
- **Menu Bar**: Control modes, speech models, history, and settings.

## 📄 License
Private / Not for redistribution.
