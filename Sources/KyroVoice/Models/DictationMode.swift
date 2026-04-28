import Foundation

public enum DictationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal
    case email
    case code

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .email:  return "Email"
        case .code:   return "Code"
        }
    }

    public var symbolName: String {
        switch self {
        case .normal: return "text.alignleft"
        case .email:  return "envelope"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        }
    }
}
