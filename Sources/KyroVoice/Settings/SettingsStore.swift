import Foundation
import SwiftUI
import Combine

/// Observable settings backed by UserDefaults. The single source of truth
/// shared by MenuBarController, SettingsView, and DictationCoordinator.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let mode             = "kv.mode"
        static let model            = "kv.model"
        static let hotkeyKeyCode    = "kv.hotkey.keyCode"
        static let hotkeyModifiers  = "kv.hotkey.modifiers"
        static let hotkeyMode       = "kv.hotkey.mode"
        static let cloudCleanup     = "kv.cloudCleanup"
        static let injectionMode    = "kv.injection.mode"
        static let perAppOverrides  = "kv.perAppOverrides"
        static let downloadedModels = "kv.downloadedModels"
    }

    @Published public var mode: DictationMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }
    @Published public var model: ModelVariant {
        didSet { defaults.set(model.rawValue, forKey: Key.model) }
    }
    @Published public var hotkey: HotkeyConfig {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Key.hotkeyModifiers)
        }
    }
    @Published public var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: Key.hotkeyMode) }
    }
    @Published public var cloudCleanupEnabled: Bool {
        didSet { defaults.set(cloudCleanupEnabled, forKey: Key.cloudCleanup) }
    }
    @Published public var injectionStrategy: InjectionStrategyKind {
        didSet { defaults.set(injectionStrategy.rawValue, forKey: Key.injectionMode) }
    }
    @Published public var downloadedModels: Set<String> {
        didSet { defaults.set(Array(downloadedModels), forKey: Key.downloadedModels) }
    }

    private init() {
        let modeRaw      = defaults.string(forKey: Key.mode)  ?? DictationMode.normal.rawValue
        let modelRaw     = defaults.string(forKey: Key.model) ?? ModelVariant.smallEN.rawValue
        let kc           = defaults.object(forKey: Key.hotkeyKeyCode)   as? Int
        let mods         = defaults.object(forKey: Key.hotkeyModifiers) as? Int
        let injRaw       = defaults.string(forKey: Key.injectionMode)   ?? InjectionStrategyKind.pasteboard.rawValue
        let downloaded   = Set(defaults.stringArray(forKey: Key.downloadedModels) ?? [])

        self.mode             = DictationMode(rawValue: modeRaw) ?? .normal
        self.downloadedModels = downloaded

        // Guard: if stored model requires explicit download but hasn't been downloaded,
        // fall back to small so the engine doesn't try to use a missing model.
        let storedVariant = ModelVariant(rawValue: modelRaw) ?? .smallEN
        if storedVariant.requiresExplicitDownload && !downloaded.contains(modelRaw) {
            self.model = .smallEN
        } else {
            self.model = storedVariant
        }

        if let kc, let mods {
            self.hotkey = HotkeyConfig(keyCode: UInt32(kc), modifiers: UInt32(mods))
        } else {
            self.hotkey = .default
        }

        self.hotkeyMode          = .pushToTalk
        self.cloudCleanupEnabled = defaults.bool(forKey: Key.cloudCleanup)
        self.injectionStrategy   = InjectionStrategyKind(rawValue: injRaw) ?? .pasteboard
    }

    /// Marks a model as successfully downloaded so the UI shows it as selectable.
    public func markDownloaded(_ variant: ModelVariant) {
        downloadedModels.insert(variant.rawValue)
    }

    /// Returns true if the variant is ready to select (either auto-downloads or has been explicitly downloaded).
    public func isReadyToUse(_ variant: ModelVariant) -> Bool {
        if !variant.requiresExplicitDownload { return true }
        return downloadedModels.contains(variant.rawValue)
    }
}

public enum InjectionStrategyKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case pasteboard
    case accessibility
    case auto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pasteboard:    return "Pasteboard + ⌘V (recommended)"
        case .accessibility: return "Accessibility (experimental)"
        case .auto:          return "Auto (try AX, fall back)"
        }
    }
}
