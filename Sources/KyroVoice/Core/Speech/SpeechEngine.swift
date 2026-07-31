import Foundation
import FluidAudio

public enum SpeechEngineError: Error, LocalizedError {
    case notReady
    case modelLoadFailed(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case cancelled
    case invalidAudio(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notReady:                   return "Speech model is not loaded yet."
        case .modelLoadFailed(let e):     return "Failed to load speech model: \(e.localizedDescription)"
        case .transcriptionFailed(let e): return "Transcription failed: \(e.localizedDescription)"
        case .cancelled:                  return "Transcription cancelled."
        case .invalidAudio(let r):        return "Invalid audio: \(r)"
        }
    }
}

/// Actor that wraps FluidAudio's Parakeet TDT recognizer. Single point of
/// access to the model.
///
/// Parakeet emits punctuation and capitalization itself, so `TextProcessor`
/// receives already-formatted text. Its punctuation rules are idempotent on
/// well-formed input, so they stay in the pipeline unchanged.
public actor SpeechEngine {
    public enum LoadState: Equatable {
        case unloaded
        case loading
        case ready
        case failed(String)
    }

    public private(set) var loadState: LoadState = .unloaded
    public private(set) var variant: ModelVariant

    private var manager: AsrManager?
    private var loadTask: Task<Void, Error>?

    public init(variant: ModelVariant = .parakeetV2) {
        self.variant = variant
    }

    /// Download (if needed) and load the model. Idempotent and safe to call
    /// concurrently: concurrent callers wait on the same task.
    public func warmUp() async throws {
        if loadState == .ready { return }
        if let task = loadTask { return try await task.value }

        loadState = .loading
        let task = Task { [variant] in
            do {
                let models = try await AsrModels.downloadAndLoad(version: variant.asrVersion)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                self.manager = manager
                self.loadState = .ready
            } catch {
                self.loadState = .failed(error.localizedDescription)
                throw SpeechEngineError.modelLoadFailed(underlying: error)
            }
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    /// Switch variant. Triggers a reload on next `warmUp()` / `transcribe`.
    public func setVariant(_ new: ModelVariant) async {
        guard new != variant else { return }
        // Cancel and forget any in-flight load, otherwise warmUp() below awaits
        // the *old* variant's task, which then installs the old model and marks
        // it ready. The newly chosen model would never load.
        loadTask?.cancel()
        loadTask = nil
        if let manager { await manager.cleanup() }
        variant = new
        manager = nil
        loadState = .unloaded
    }

    /// Transcribe a 16 kHz mono Float32 sample buffer.
    public func transcribe(samples: [Float]) async throws -> String {
        if loadState != .ready { try await warmUp() }
        guard let manager else { throw SpeechEngineError.notReady }
        guard !samples.isEmpty else {
            throw SpeechEngineError.invalidAudio(reason: "empty buffer")
        }

        // Sanity check: pure zeros mean the recorder produced silence.
        let preview = samples.prefix(min(samples.count, 16_000))
        let energy = preview.reduce(Float(0)) { $0 + $1 * $1 }
        if energy == 0 {
            throw SpeechEngineError.invalidAudio(reason: "silent buffer")
        }

        do {
            try Task.checkCancellation()
            // Fresh decoder state per utterance. Push-to-talk dictations are
            // independent, so carrying transducer state across them would leak
            // context from one injection into the next.
            let layers = await manager.decoderLayerCount
            var state = try TdtDecoderState(decoderLayers: layers)
            let result = try await manager.transcribe(samples, decoderState: &state)
            try Task.checkCancellation()
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw SpeechEngineError.cancelled
        } catch {
            throw SpeechEngineError.transcriptionFailed(underlying: error)
        }
    }
}
