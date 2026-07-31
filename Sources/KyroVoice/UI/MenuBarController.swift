import Foundation
import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem and its NSMenu. Talks to the DictationCoordinator
/// and observes SettingsStore for live menu updates.
@MainActor
public final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: DictationCoordinator
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    private weak var startStopItem: NSMenuItem?
    private var modeItems: [DictationMode: NSMenuItem] = [:]
    private var modelItems: [ModelVariant: NSMenuItem] = [:]

    public init(coordinator: DictationCoordinator, settings: SettingsStore) {
        self.coordinator = coordinator
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        statusItem.menu = buildMenu()
        observeSettings()
        observeCoordinator()
    }

    /// Menu-bar metrics: 15 pt medium reads level with the system's own items.
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "KyroVoice - local voice dictation"
        applyIcon(recording: false)
    }

    /// One glyph, two states: a waveform that goes red while capturing. Same
    /// silhouette in both states, so neighbouring menu-bar items never shift.
    private func applyIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "KyroVoice")?
            .withSymbolConfiguration(Self.symbolConfig)
        image?.isTemplate = true
        button.image = image
        // If the symbol were ever unavailable the button would render empty and
        // look like the app had vanished; a text fallback keeps it findable.
        button.title = image == nil ? "KV" : ""
        button.contentTintColor = recording ? .systemRed : nil
    }

    private func observeSettings() {
        settings.$mode.sink { [weak self] new in
            self?.refreshModeChecks(for: new)
        }.store(in: &cancellables)

        settings.$model.sink { [weak self] new in
            self?.refreshModelChecks(for: new)
        }.store(in: &cancellables)

    }

    private func observeCoordinator() {
        coordinator.$isRecording
            // Not RunLoop.main: that schedules in .default mode only, so while
            // the status menu is open (NSEventTrackingRunLoopMode) the icon and
            // the Start/Stop title stop updating, which is exactly when the
            // user is looking at them. The publisher already fires on the main
            // actor, so no hop is needed at all.
            .sink { [weak self] recording in
                guard let self else { return }
                self.applyIcon(recording: recording)
                self.refreshStartStopTitle(recording: recording)
            }
            .store(in: &cancellables)

        // The title depends on hotkeyMode too, which used to go unobserved:
        // switching to "Tap to toggle" left it reading "Hold …" until the next
        // recording.
        settings.$hotkeyMode
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshStartStopTitle(recording: self.coordinator.isRecording)
            }
            .store(in: &cancellables)
    }

    private func refreshStartStopTitle(recording: Bool) {
        if recording {
            startStopItem?.title = "Stop dictation"
        } else if settings.hotkeyMode == .pushToTalk {
            // Was hardcoded to "⌘⇧Space" and read "Hold … to dictation".
            startStopItem?.title = "Hold \(settings.hotkey.displayString) to dictate"
        } else {
            startStopItem?.title = "Start dictation"
        }
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Start/Stop
        let toggle = NSMenuItem(
            title: "Start dictation",
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        startStopItem = toggle

        menu.addItem(.separator())

        // Mode submenu
        let modeRoot = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in DictationMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (mode == settings.mode) ? .on : .off
            modeMenu.addItem(item)
            modeItems[mode] = item
        }
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        // Model submenu
        let modelRoot = NSMenuItem(title: "Speech model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for variant in ModelVariant.allCases {
            let item = NSMenuItem(
                title: variant.displayName,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = variant.rawValue
            item.state = (variant == settings.model) ? .on : .off
            modelMenu.addItem(item)
            modelItems[variant] = item
        }
        modelRoot.submenu = modelMenu
        menu.addItem(modelRoot)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(
            title: "History…",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(
            title: "Quit KyroVoice",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        Task { await coordinator.userToggle() }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DictationMode(rawValue: raw) else { return }
        settings.mode = mode
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let variant = ModelVariant(rawValue: raw) else { return }
        // Assigning settings.model is enough: DictationCoordinator subscribes to
        // settings.$model and reloads the engine itself. Calling modelChanged
        // here too reloaded the model twice on every menu pick.
        settings.model = variant
    }

    @objc private func openHistory() {
        HistoryWindow.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - State refresh

    private func refreshModeChecks(for active: DictationMode) {
        for (mode, item) in modeItems {
            item.state = (mode == active) ? .on : .off
        }
    }

    private func refreshModelChecks(for active: ModelVariant) {
        for (variant, item) in modelItems {
            item.state = (variant == active) ? .on : .off
        }
    }
}
