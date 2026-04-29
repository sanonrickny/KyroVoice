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
    private weak var cloudItem: NSMenuItem?

    public init(coordinator: DictationCoordinator, settings: SettingsStore) {
        self.coordinator = coordinator
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        statusItem.menu = buildMenu()
        observeSettings()
        observeCoordinator()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.title = "KV"
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "KyroVoice")
            button.image?.isTemplate = true
            button.toolTip = "KyroVoice — local voice dictation"
        }
    }

    private func observeSettings() {
        settings.$mode.sink { [weak self] new in
            self?.refreshModeChecks(for: new)
        }.store(in: &cancellables)

        settings.$model.sink { [weak self] new in
            self?.refreshModelChecks(for: new)
        }.store(in: &cancellables)

        settings.$cloudCleanupEnabled.sink { [weak self] enabled in
            self?.cloudItem?.state = enabled ? .on : .off
        }.store(in: &cancellables)
    }

    private func observeCoordinator() {
        coordinator.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                guard let self else { return }
                if let button = self.statusItem.button {
                    let symbol = recording ? "mic.circle.fill" : "mic.circle"
                    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KyroVoice")
                    button.image?.isTemplate = true
                    button.contentTintColor = recording ? .systemRed : nil
                }
                
                let isPushToTalk = self.settings.hotkeyMode == .pushToTalk
                self.startStopItem?.title = recording ? "Stop dictation" : (isPushToTalk ? "Hold ⌘⇧Space to dictation" : "Start dictation")
            }
            .store(in: &cancellables)
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
        let modelRoot = NSMenuItem(title: "Whisper model", action: nil, keyEquivalent: "")
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

        // Cloud cleanup toggle
        let cloud = NSMenuItem(
            title: "Cloud AI cleanup",
            action: #selector(toggleCloud),
            keyEquivalent: ""
        )
        cloud.target = self
        cloud.state = settings.cloudCleanupEnabled ? .on : .off
        menu.addItem(cloud)
        cloudItem = cloud

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
        settings.model = variant
        Task { await coordinator.modelChanged(to: variant) }
    }

    @objc private func toggleCloud() {
        settings.cloudCleanupEnabled.toggle()
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
