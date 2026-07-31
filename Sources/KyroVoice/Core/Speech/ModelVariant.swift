import Foundation
import FluidAudio

/// The speech-recognition model to run. Both are NVIDIA Parakeet TDT 0.6B
/// converted to CoreML by FluidAudio and executed on the Apple Neural Engine.
///
/// Raw values are persisted in UserDefaults. They intentionally do not match
/// the old `openai_whisper-*` strings, so an existing install falls through
/// `ModelVariant(rawValue:) ?? .parakeetV2` and lands on the better model.
public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeetV2 = "parakeet-tdt-0.6b-v2"
    case parakeetV3 = "parakeet-tdt-0.6b-v3"

    public var id: String { rawValue }

    /// FluidAudio's model selector.
    public var asrVersion: AsrModelVersion {
        switch self {
        case .parakeetV2: return .v2
        case .parakeetV3: return .v3
        }
    }

    public var displayName: String {
        switch self {
        case .parakeetV2: return "Parakeet v2 · English"
        case .parakeetV3: return "Parakeet v3 · Multilingual"
        }
    }

    public var shortDescription: String {
        switch self {
        case .parakeetV2: return "≈450 MB · 2.1% word error rate · most accurate English (recommended)"
        case .parakeetV3: return "≈600 MB · 2.6% word error rate · 25 European languages"
        }
    }

    public var approxDownloadMB: Int {
        switch self {
        case .parakeetV2: return 450
        case .parakeetV3: return 600
        }
    }

    /// v2 auto-downloads on first dictation (it is the default). v3 is opt-in,
    /// so the user is not surprised by a second 600 MB transfer.
    public var requiresExplicitDownload: Bool {
        self == .parakeetV3
    }
}
