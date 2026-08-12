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
    private var whisper: SpeechEngine!
    private var processor: TextProcessor!
    private var injector: ClipboardInjector!
    private var modeResolver: ModeResolver!
    private var overlayState: OverlayState!
    private var overlay: FloatingOverlay!
    private var coordinator: DictationCoordinator!
    private var menuBar: MenuBarController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Renders the UI to PNGs for the docs site and exits. Runs before the
        // dependency graph so no hotkey is registered and no mic is opened.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            UISnapshot.run(into: CommandLine.arguments.indices.contains(i + 1)
                ? CommandLine.arguments[i + 1] : ".")
        }

        NSApp.setActivationPolicy(.accessory)

        // Seed permissions service eagerly so settings UI reflects truth.
        _ = PermissionsHolder.shared.service

        // Build dependency graph.
        recorder     = AudioRecorder()
        whisper      = SpeechEngine(variant: settings.model)
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

        // Warm up the speech model in the background so first hotkey press isn't slow.
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
            // RegisterEventHotKey fails with eventHotKeyExistsErr when another
            // app already owns the combination. In an .accessory app with no
            // console that used to be invisible: the whole app just did nothing.
            NSLog("KyroVoice: failed to register hotkey \(settings.hotkey.displayString)")
            overlayState.phase = .error("\(settings.hotkey.displayString) is already used by another app. KyroVoice can't listen for it.")
            overlay.show()
            overlay.scheduleHide(after: 8)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
    }
}
