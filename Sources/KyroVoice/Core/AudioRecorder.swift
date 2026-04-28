import Foundation
import AVFoundation
import AppKit

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case engineStartFailed(underlying: Error)
    case converterCreationFailed
    case conversionFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access denied. Open System Settings → Privacy & Security → Microphone and enable KyroVoice."
        case .engineStartFailed(let e):
            return "Audio engine failed to start: \(e.localizedDescription)"
        case .converterCreationFailed:
            return "Could not build an audio converter to 16 kHz mono Float32."
        case .conversionFailed(let e):
            return "Audio conversion failed: \(e.localizedDescription)"
        }
    }
}

/// Captures default-input audio and produces 16 kHz mono Float32 PCM
/// suitable for WhisperKit. The engine is long-lived; recording is gated by a
/// flag flipped by `start()` / `stop()` so the hotkey-to-first-sample latency
/// stays well under 200 ms.
public final class AudioRecorder {
    public typealias LevelHandler = @Sendable (Float) -> Void

    public enum State { case idle, preparing, ready, recording, denied }

    public private(set) var state: State = .idle

    public var levelHandler: LevelHandler?

    /// Sample rate WhisperKit expects.
    public static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var inputFormat: AVAudioFormat?

    private let lock = NSLock()
    private var capturing = false
    private var samples: [Float] = []

    public init() {}

    // MARK: - Lifecycle

    /// Request mic permission and start the engine. Call once at app launch.
    public func prepare() async throws {
        state = .preparing

        let granted = await Self.requestMicrophonePermission()
        guard granted else {
            state = .denied
            throw AudioRecorderError.microphoneDenied
        }

        try installTapAndStartEngine()
        state = .ready
    }

    private func installTapAndStartEngine() throws {
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        inputFormat = nativeFormat

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.converterCreationFailed
        }
        targetFormat = target

        guard let conv = AVAudioConverter(from: nativeFormat, to: target) else {
            throw AudioRecorderError.converterCreationFailed
        }
        converter = conv

        // Buffer 1024 frames @ ~48kHz native ≈ 21 ms latency.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioRecorderError.engineStartFailed(underlying: error)
        }
    }

    @objc private func handleConfigChange() {
        // Device or sample-rate changed (e.g. user switched mic). Reinstall.
        do {
            engine.stop()
            try installTapAndStartEngine()
        } catch {
            NSLog("KyroVoice: audio reconfigure failed: \(error)")
        }
    }

    // MARK: - Capture control

    public func start() throws {
        guard state == .ready || state == .idle else {
            if state == .denied { throw AudioRecorderError.microphoneDenied }
            return
        }
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate) * 60) // 60 s headroom
        capturing = true
        lock.unlock()
        state = .recording
    }

    @discardableResult
    public func stop() -> [Float] {
        lock.lock()
        capturing = false
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        if state == .recording { state = .ready }
        return captured
    }

    // MARK: - Tap handler

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Always compute level (so overlay can show a quiet bar even pre-record).
        let rms = Self.rms(of: buffer)
        if let levelHandler { levelHandler(rms) }

        lock.lock()
        let isCapturing = capturing
        lock.unlock()
        guard isCapturing,
              let converter = converter,
              let target = targetFormat else { return }

        // frameCapacity for output: ratio of sample rates * input frames + slack.
        let inputRate = buffer.format.sampleRate
        let ratio = target.sampleRate / inputRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: capacity
        ) else { return }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            NSLog("KyroVoice: convert error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        guard let channelPtr = outBuffer.floatChannelData?[0] else { return }
        let count = Int(outBuffer.frameLength)
        guard count > 0 else { return }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channelPtr, count: count))
        lock.unlock()
    }

    // MARK: - Helpers

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let ptr = channels[0]
        var sum: Float = 0
        for i in 0..<frames {
            let s = ptr[i]
            sum += s * s
        }
        return (sum / Float(frames)).squareRoot()
    }

    private static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
