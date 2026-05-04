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
    @Published public var audioLevel: Float = 0
    @Published public var transcriptPreview: String = ""

    private var normalizer = LiveAudioLevelNormalizer()

    public init() {}

    /// Push a raw RMS value through the adaptive normalizer into a 0–1 display level.
    public func pushLevel(_ rms: Float) {
        audioLevel = normalizer.normalizedLevel(forRMS: rms)
    }

    public func resetLevels() {
        normalizer.reset()
        audioLevel = 0
    }
}

// MARK: - Adaptive audio level normalizer (ported from FreeFlow/Wispr Flow)

/// Converts raw RMS to a perceptually normalized 0–1 display level using
/// an adaptive dB noise floor and peak ceiling with fast-attack/slow-release smoothing.
private struct LiveAudioLevelNormalizer {
    private static let minimumRMS: Float = 0.00001
    private static let minSpanDB: Float = 18
    private static let peakHeadroomDB: Float = 8
    private static let speechGateMarginDB: Float = 3
    private static let minimumVisibleActiveLevel: Float = 0.12
    private static let noiseGateNormalizedThreshold: Float = 0.06
    private static let floorRiseWindowDB: Float = 4
    private static let floorFallBlend: Float = 0.12
    private static let floorRiseBlend: Float = 0.02
    private static let peakAttackBlend: Float = 0.55
    private static let peakReleaseBlend: Float = 0.04
    private static let displayAttackBlend: Float = 0.45
    private static let displayReleaseBlend: Float = 0.12

    private var noiseFloorDB: Float = -55
    private var peakCeilingDB: Float = -37
    private var displayLevel: Float = 0

    mutating func reset() {
        noiseFloorDB = -55
        peakCeilingDB = -37
        displayLevel = 0
    }

    mutating func normalizedLevel(forRMS rms: Float) -> Float {
        let levelDB = 20 * log10f(max(rms, Self.minimumRMS))

        updateNoiseFloor(with: levelDB)
        updatePeakCeiling(with: levelDB)

        let displayCeilingDB = peakCeilingDB + Self.peakHeadroomDB
        let dynamicSpan = max(displayCeilingDB - noiseFloorDB, Self.minSpanDB + Self.peakHeadroomDB)
        var normalized = clamp((levelDB - noiseFloorDB) / dynamicSpan)
        let isActiveSpeech = levelDB >= noiseFloorDB + Self.speechGateMarginDB

        if normalized < Self.noiseGateNormalizedThreshold && !isActiveSpeech {
            normalized = 0
        } else if isActiveSpeech {
            normalized = max(normalized, Self.minimumVisibleActiveLevel)
        }

        let blend = normalized > displayLevel ? Self.displayAttackBlend : Self.displayReleaseBlend
        displayLevel = mix(displayLevel, normalized, blend)
        return displayLevel
    }

    private mutating func updateNoiseFloor(with levelDB: Float) {
        let ceilingLimitedLevel = min(levelDB, peakCeilingDB - Self.minSpanDB)
        if ceilingLimitedLevel <= noiseFloorDB {
            noiseFloorDB = mix(noiseFloorDB, ceilingLimitedLevel, Self.floorFallBlend)
        } else if ceilingLimitedLevel <= noiseFloorDB + Self.floorRiseWindowDB {
            noiseFloorDB = mix(noiseFloorDB, ceilingLimitedLevel, Self.floorRiseBlend)
        }
    }

    private mutating func updatePeakCeiling(with levelDB: Float) {
        let minimumCeiling = noiseFloorDB + Self.minSpanDB
        if levelDB >= peakCeilingDB {
            peakCeilingDB = mix(peakCeilingDB, levelDB, Self.peakAttackBlend)
        } else {
            peakCeilingDB = mix(peakCeilingDB, max(levelDB, minimumCeiling), Self.peakReleaseBlend)
        }
        peakCeilingDB = max(peakCeilingDB, minimumCeiling)
    }

    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    private func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }
}
