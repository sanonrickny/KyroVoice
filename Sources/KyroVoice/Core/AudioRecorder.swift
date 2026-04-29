import Foundation
import AVFoundation
import AppKit
import KyroVoiceObjC

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case engineStartFailed(underlying: Error)
    case converterCreationFailed
    case conversionFailed(underlying: Error)
    case notReady

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
        case .notReady:
            return "Audio engine is still initialising. Please try again in a moment."
        }
    }
}

/// Captures default-input audio and produces 16 kHz mono Float32 PCM
/// suitable for WhisperKit. The engine stays running between utterances, but the
/// input tap is installed only while recording so macOS does not show an active
/// microphone / capture audio when idle.
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

    private var tapInstalled = false
    private var configObserverRegistered = false

    public init() {}

    // MARK: - Lifecycle

    /// Request mic permission and start the engine (without an input tap until recording).
    public func prepare() async throws {
        state = .preparing

        let granted = await Self.requestMicrophonePermission()
        guard granted else {
            state = .denied
            throw AudioRecorderError.microphoneDenied
        }

        registerConfigObserverIfNeeded()
        do {
            try connectEngineWithoutTap()
        } catch {
            state = .idle  // allow retry on next start() rather than sticking at .preparing
            throw error
        }
        state = .ready
    }

    private func registerConfigObserverIfNeeded() {
        guard !configObserverRegistered else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        configObserverRegistered = true
    }

    /// Builds the converter and runs the engine with no input tap (idle — mic not actively captured).
    private func connectEngineWithoutTap() throws {
        removeTapIfNeeded()
        engine.stop()

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.converterCreationFailed
        }
        targetFormat = target

        // Accessing inputNode forces it into the AVAudioEngineGraph before start —
        // on macOS 26+ start() throws if neither inputNode nor outputNode is in the graph.
        _ = engine.inputNode

        do {
            try KVAudioEngineHelper.start(engine)
        } catch {
            throw AudioRecorderError.engineStartFailed(underlying: error)
        }

        // Read format AFTER engine starts — before start, inputNode may report a
        // zero-channel placeholder on macOS, making AVAudioConverter return nil.
        let nativeFormat = engine.inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioRecorderError.converterCreationFailed
        }
        inputFormat = nativeFormat

        guard let conv = AVAudioConverter(from: nativeFormat, to: target) else {
            throw AudioRecorderError.converterCreationFailed
        }
        converter = conv
    }

    /// Buffer 1024 frames @ ~48kHz native ≈ 21 ms latency.
    private func installTapIfNeeded() throws {
        guard !tapInstalled else { return }
        guard let nativeFormat = inputFormat else {
            throw AudioRecorderError.converterCreationFailed
        }

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        tapInstalled = true
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    @objc private func handleConfigChange() {
        let wasRecording = capturing
        do {
            try connectEngineWithoutTap()
            if wasRecording {
                try installTapIfNeeded()
            }
        } catch {
            NSLog("KyroVoice: audio reconfigure failed: \(error)")
        }
    }

    // MARK: - Capture control

    public func start() throws {
        switch state {
        case .ready, .idle: break
        case .denied: throw AudioRecorderError.microphoneDenied
        case .preparing: throw AudioRecorderError.notReady
        case .recording: return
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate) * 60)
        capturing = true
        lock.unlock()

        // Engine must be running for the tap to receive audio. It normally stays
        // running between recordings, but restart it here as a safety net in case
        // it stopped due to a device change or other external event.
        if !engine.isRunning {
            do {
                try KVAudioEngineHelper.start(engine)
            } catch {
                lock.lock(); capturing = false; lock.unlock()
                throw AudioRecorderError.engineStartFailed(underlying: error)
            }
        }

        do {
            try installTapIfNeeded()
        } catch {
            lock.lock()
            capturing = false
            lock.unlock()
            throw error
        }

        state = .recording
    }

    public func stop() -> [Float] {
        lock.lock()
        capturing = false
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        // Only remove the tap — keep the engine running so the next start()
        // can install a tap immediately without restarting. macOS shows the
        // microphone indicator only while a tap is active, not while the
        // engine idles, so this matches the intended privacy behaviour.
        removeTapIfNeeded()

        if state == .recording { state = .ready }
        return captured
    }

    // MARK: - Tap handler

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
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
