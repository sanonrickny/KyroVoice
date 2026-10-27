import Foundation
import FluidAudio

/// The speech-recognition model to run. Both are NVIDIA Parakeet TDT 0.6B
/// converted to CoreML by FluidAudio and executed on the Apple Neural Engine.
/// Ultra is a post-trained v3 that beats it on every benchmark at the same
/// speed, so it replaced v3. A stored v3 selection falls back to v2.
///
/// Raw values are persisted in UserDefaults. They intentionally do not match
/// the old `openai_whisper-*` strings, so an existing install falls through
/// `ModelVariant(rawValue:) ?? .parakeetV2` and lands on the better model.
public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeetV2 = "parakeet-tdt-0.6b-v2"
    case parakeetUltra = "parakeet-ultra"

    public var id: String { rawValue }

    /// FluidAudio's model selector.
    public var asrVersion: AsrModelVersion {
        switch self {
        case .parakeetV2: return .v2
        case .parakeetUltra: return .ultra
        }
    }

    public var displayName: String {
        switch self {
        case .parakeetV2: return "Parakeet v2 · English"
        case .parakeetUltra: return "Parakeet Ultra · Multilingual"
        }
    }

    public var shortDescription: String {
        switch self {
        case .parakeetV2: return "≈450 MB · 2.1% word error rate · most accurate English (recommended)"
        case .parakeetUltra: return "≈630 MB · 2.1% word error rate · 25 European languages"
        }
    }

    public var approxDownloadMB: Int {
        switch self {
        case .parakeetV2: return 450
        case .parakeetUltra: return 630
        }
    }

    /// v2 auto-downloads on first dictation (it is the default). Ultra is opt-in,
    /// so the user is not surprised by a second 630 MB transfer.
    public var requiresExplicitDownload: Bool {
        self == .parakeetUltra
    }
}
