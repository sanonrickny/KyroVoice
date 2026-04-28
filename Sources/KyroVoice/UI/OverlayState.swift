import Foundation
import SwiftUI

/// Observable state for the floating overlay. The DictationCoordinator
/// drives transitions; FloatingOverlay observes and renders.
@MainActor
public final class OverlayState: ObservableObject {
    public enum Phase: Equatable {
        case hidden
        case listening
        case processing
        case injected
        case error(String)
    }

    @Published public var phase: Phase = .hidden
    @Published public var levels: [Float] = Array(repeating: 0, count: 7)
    @Published public var transcriptPreview: String = ""

    public init() {}

    /// Push a new level (0…1ish RMS) into the rolling window.
    public func pushLevel(_ rms: Float) {
        // Compress dynamic range — RMS rarely exceeds ~0.3 for speech.
        let scaled = min(1.0, max(0.05, rms * 6.0))
        levels.removeFirst()
        levels.append(scaled)
    }

    public func resetLevels() {
        levels = Array(repeating: 0.05, count: 7)
    }
}
