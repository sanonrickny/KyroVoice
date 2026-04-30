import Foundation
import WhisperKit

public enum WhisperEngineError: Error, LocalizedError {
    case notReady
    case modelLoadFailed(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case cancelled
    case invalidAudio(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notReady:                   return "Whisper model is not loaded yet."
        case .modelLoadFailed(let e):     return "Failed to load Whisper model: \(e.localizedDescription)"
        case .transcriptionFailed(let e): return "Transcription failed: \(e.localizedDescription)"
        case .cancelled:                  return "Transcription cancelled."
        case .invalidAudio(let r):        return "Invalid audio: \(r)"
        }
    }
}

/// Actor that wraps WhisperKit. Single point of access to the model.
public actor WhisperEngine {
    public enum LoadState: Equatable {
        case unloaded
        case loading
        case ready
        case failed(String)
    }

    public private(set) var loadState: LoadState = .unloaded
    public private(set) var variant: ModelVariant

    private var kit: WhisperKit?
    private var loadTask: Task<Void, Error>?

    public init(variant: ModelVariant = .smallEN) {
        self.variant = variant
    }

    /// Download (if needed) and load the model. Idempotent and safe to call
    /// concurrently — concurrent callers wait on the same task.
    public func warmUp() async throws {
        if loadState == .ready { return }
        if let task = loadTask { return try await task.value }

        loadState = .loading
        let task = Task { [variant] in
            do {
                let config = WhisperKitConfig(
                    model: variant.rawValue,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true,
                    download: true
                )
                let kit = try await WhisperKit(config)
                self.kit = kit
                self.loadState = .ready
            } catch {
                self.loadState = .failed(error.localizedDescription)
                throw WhisperEngineError.modelLoadFailed(underlying: error)
            }
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    /// Switch variant. Triggers a reload on next `warmUp()` / `transcribe`.
    public func setVariant(_ new: ModelVariant) {
        guard new != variant else { return }
        variant = new
        kit = nil
        loadState = .unloaded
    }

    /// Transcribe a 16 kHz mono Float32 sample buffer.
    /// `partialHandler` (optional) receives best-guess text as decoding progresses.
    public func transcribe(
        samples: [Float],
        partialHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if loadState != .ready { try await warmUp() }
        guard let kit else { throw WhisperEngineError.notReady }
        guard !samples.isEmpty else {
            throw WhisperEngineError.invalidAudio(reason: "empty buffer")
        }

        // Sanity check: pure zeros mean the recorder produced silence.
        let preview = samples.prefix(min(samples.count, 16_000))
        let energy = preview.reduce(Float(0)) { $0 + $1 * $1 }
        if energy == 0 {
            throw WhisperEngineError.invalidAudio(reason: "silent buffer")
        }

        // Pin language and strip special tokens so the model can't return raw
        // token strings when it detects no speech. Keep all thresholds at their
        // defaults — only disable the no-speech gate so very short utterances
        // still produce output rather than empty string.
        let opts = DecodingOptions(
            language: "en",
            skipSpecialTokens: true,
            noSpeechThreshold: nil   // disable the gate; let Whisper return whatever it hears
        )

        do {
            try Task.checkCancellation()
            let results: [TranscriptionResult]
            if let partialHandler {
                results = try await kit.transcribe(
                    audioArray: samples,
                    decodeOptions: opts
                ) { progress in
                    partialHandler(progress.text)
                    return !Task.isCancelled
                }
            } else {
                results = try await kit.transcribe(
                    audioArray: samples,
                    decodeOptions: opts,
                    callback: nil
                )
            }
            try Task.checkCancellation()
            let text = results.map { $0.text }.joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw WhisperEngineError.cancelled
        } catch {
            throw WhisperEngineError.transcriptionFailed(underlying: error)
        }
    }
}
