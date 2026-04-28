import Foundation
import Carbon.HIToolbox

public struct HotkeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Default: ⌘ ⇧ Space.
    public static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    public var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:        return "Space"
        case kVK_Return:       return "Return"
        case kVK_Escape:       return "Esc"
        case kVK_Tab:          return "Tab"
        case kVK_F1...kVK_F20:
            return "F\(Int(keyCode) - kVK_F1 + 1)"
        case kVK_ANSI_A...kVK_ANSI_Z:
            let scalar = UnicodeScalar(UInt8(Int(keyCode) - kVK_ANSI_A) + 0x41)
            return String(Character(scalar))
        default:
            return "Key\(keyCode)"
        }
    }
}

public enum HotkeyMode: String, Codable, CaseIterable, Sendable {
    case pushToTalk
    case toggle

    public var displayName: String {
        switch self {
        case .pushToTalk: return "Push to talk"
        case .toggle:     return "Tap to toggle"
        }
    }
}
