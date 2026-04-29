import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var hotkey: HotkeyManager!
    private var recorder: AudioRecorder!
    private var whisper: WhisperEngine!
    private var processor: TextProcessor!
    private var injector: ClipboardInjector!
    private var modeResolver: ModeResolver!
    private var overlayState: OverlayState!
    private var overlay: FloatingOverlay!
    private var coordinator: DictationCoordinator!
    private var menuBar: MenuBarController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Seed permissions service eagerly so settings UI reflects truth.
        _ = PermissionsHolder.shared.service

        // Build dependency graph.
        recorder     = AudioRecorder()
        whisper      = WhisperEngine(variant: settings.model)
        processor    = TextProcessor()
        injector     = ClipboardInjector(strategy: settings.injectionStrategy)
        modeResolver = ModeResolver()
        overlayState = OverlayState()
        overlay      = FloatingOverlay(state: overlayState)
        coordinator  = DictationCoordinator(
            settings: settings,
            recorder: recorder,
            whisper: whisper,
            processor: processor,
            injector: injector,
            modeResolver: modeResolver,
            overlayState: overlayState,
            overlay: overlay
        )
        menuBar = MenuBarController(coordinator: coordinator, settings: settings)

        settings.$injectionStrategy
            .dropFirst()
            .sink { [weak self] strategy in
                self?.injector.setStrategy(strategy)
            }
            .store(in: &cancellables)

        // Prepare audio engine + request mic permission on launch.
        Task {
            do {
                try await recorder.prepare()
            } catch {
                NSLog("KyroVoice: audio prepare failed: \(error.localizedDescription)")
            }
        }

        // Warm up Whisper in the background so first hotkey press isn't slow.
        Task.detached(priority: .utility) { [whisper] in
            try? await whisper?.warmUp()
        }

        // Register the global hotkey.
        hotkey = HotkeyManager()
        hotkey.onHotkeyDown = { [weak self] in
            self?.coordinator.hotkeyPressed()
        }
        hotkey.onHotkeyUp = { [weak self] in
            self?.coordinator.hotkeyReleased()
        }
        if !hotkey.register(settings.hotkey) {
            NSLog("KyroVoice: failed to register hotkey \(settings.hotkey.displayString)")
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
    }
}
