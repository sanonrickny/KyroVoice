import Foundation

public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case baseEN       = "openai_whisper-base.en"
    case smallEN      = "openai_whisper-small.en"
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .baseEN:       return "Base · English"
        case .smallEN:      return "Small · English"
        case .largeV3Turbo: return "Large v3 Turbo"
        }
    }

    public var shortDescription: String {
        switch self {
        case .baseEN:       return "≈75 MB · Fastest, great for quick notes"
        case .smallEN:      return "≈250 MB · Balanced speed & accuracy (recommended)"
        case .largeV3Turbo: return "≈632 MB · Best accuracy with fast decode · English & multilingual"
        }
    }

    public var approxDownloadMB: Int {
        switch self {
        case .baseEN:       return 75
        case .smallEN:      return 250
        case .largeV3Turbo: return 632
        }
    }

    /// Large v3 Turbo requires an explicit download before first use;
    /// the smaller models auto-download on first dictation.
    public var requiresExplicitDownload: Bool {
        self == .largeV3Turbo
    }
}
