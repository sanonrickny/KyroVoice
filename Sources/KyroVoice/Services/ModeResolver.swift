import Foundation
import AppKit

/// Maps the frontmost application's bundle ID to a DictationMode.
public final class ModeResolver {
    public var defaultMode: DictationMode = .normal

    public var overrides: [String: DictationMode] = [
        "com.microsoft.VSCode":             .code,
        "com.todesktop.230313mzl4w4u92":    .code,   // Cursor
        "com.apple.dt.Xcode":               .code,
        "com.jetbrains.intellij":           .code,
        "com.jetbrains.pycharm":            .code,
        "com.googlecode.iterm2":            .code,
        "com.apple.Terminal":               .code,
        "com.apple.mail":                   .email,
        "com.microsoft.Outlook":            .email
    ]

    public init() {}

    public func resolve(default fallback: DictationMode? = nil) -> DictationMode {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if let mapped = overrides[bid] { return mapped }
        return fallback ?? defaultMode
    }
}
