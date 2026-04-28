import Foundation

public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case baseEN  = "openai_whisper-base.en"
    case smallEN = "openai_whisper-small.en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .baseEN:  return "Base (≈75 MB, fastest)"
        case .smallEN: return "Small (≈250 MB, recommended)"
        }
    }

    public var approxDownloadMB: Int {
        switch self {
        case .baseEN:  return 75
        case .smallEN: return 250
        }
    }
}
