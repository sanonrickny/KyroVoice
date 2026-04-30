import Foundation
import AVFoundation
import AppKit
import KyroVoiceObjC

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case engineStartFailed(underlying: Error)
    case formatUnavailable
    case notReady

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access denied. Open System Settings → Privacy & Security → Microphone and enable KyroVoice."
        case .engineStartFailed(let e):
            return "Audio engine failed to start: \(e.localizedDescription)"
        case .formatUnavailable:
            return "Could not prepare 16 kHz mono Float32 audio format."
        case .notReady:
            return "Audio engine is still initialising. Please try again in a moment."
        }
    }
}

/// Captures default-input audio and produces 16 kHz mono Float32 PCM
/// suitable for WhisperKit.
///
/// AVAudioEngine performs the sample-rate and channel-count conversion
/// automatically when you specify the target format directly in `installTap`.
/// No separate AVAudioConverter is needed — the engine's built-in converter
/// is more reliable across engine stop/start cycles than a manually held
/// AVAudioConverter instance.
public final class AudioRecorder {
    public typealias LevelHandler = @Sendable (Float) -> Void

    public enum State { case idle, preparing, ready, recording, denied }

    public private(set) var state: State = .idle
    public var levelHandler: LevelHandler?

    public static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var targetFormat: AVAudioFormat?

    private let lock = NSLock()
    private var capturing = false
    private var samples: [Float] = []

    private var tapInstalled = false
    private var configObserverRegistered = false

    public init() {}

    // MARK: - Lifecycle

    public func prepare() async throws {
        state = .preparing

        let granted = await Self.requestMicrophonePermission()
        guard granted else {
            state = .denied
            throw AudioRecorderError.microphoneDenied
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            state = .idle
            throw AudioRecorderError.formatUnavailable
        }
        targetFormat = target

        registerConfigObserverIfNeeded()

        // Touch inputNode to force it into the engine graph before start.
        // On macOS 26+, starting the engine throws if no nodes are connected.
        _ = engine.inputNode
        do {
            try KVAudioEngineHelper.start(engine)
            engine.stop()
        } catch {
            state = .idle
            throw AudioRecorderError.engineStartFailed(underlying: error)
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

    @objc private func handleConfigChange() {
        let wasRecording = capturing
        removeTapIfNeeded()
        engine.stop()
        _ = engine.inputNode
        do {
            try KVAudioEngineHelper.start(engine)
            if wasRecording {
                try installTapIfNeeded()
            } else {
                engine.stop()
            }
        } catch {
            NSLog("KyroVoice: audio reconfigure failed: \(error)")
        }
    }

    // MARK: - Capture control

    public func start() throws {
        switch state {
        case .ready, .idle: break
        case .denied:    throw AudioRecorderError.microphoneDenied
        case .preparing: throw AudioRecorderError.notReady
        case .recording: return
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate) * 60)
        capturing = true
        lock.unlock()

        do {
            try KVAudioEngineHelper.start(engine)
        } catch {
            lock.lock(); capturing = false; lock.unlock()
            throw AudioRecorderError.engineStartFailed(underlying: error)
        }

        do {
            try installTapIfNeeded()
        } catch {
            lock.lock(); capturing = false; lock.unlock()
            engine.stop()
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

        removeTapIfNeeded()
        engine.stop()

        if state == .recording { state = .ready }
        return captured
    }

    // MARK: - Tap

    private func installTapIfNeeded() throws {
        guard !tapInstalled else { return }
        guard let targetFmt = targetFormat else {
            throw AudioRecorderError.formatUnavailable
        }

        let input = engine.inputNode
        let nativeFmt = input.inputFormat(forBus: 0)
        // Build a converter now (before the tap block runs) so it's reused
        // across every buffer callback rather than allocated per-buffer.
        guard let converter = AVAudioConverter(from: nativeFmt, to: targetFmt) else {
            throw AudioRecorderError.formatUnavailable
        }

        input.removeTap(onBus: 0)
        // Install with nil (native format): macOS 26 throws an NSException when
        // a non-native sample rate is passed. We convert to 16 kHz Float32 manually.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buf, _ in
            self?.convertAndHandle(buf, converter: converter, targetFmt: targetFmt)
        }
        tapInstalled = true
    }

    private func convertAndHandle(_ buffer: AVAudioPCMBuffer,
                                   converter: AVAudioConverter,
                                   targetFmt: AVAudioFormat) {
        let ratio = targetFmt.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFmt, frameCapacity: cap) else { return }
        var fed = false
        let status = converter.convert(to: out, error: nil) { _, flag in
            if fed { flag.pointee = .noDataNow; return nil }
            fed = true; flag.pointee = .haveData; return buffer
        }
        guard status != .error else { return }
        handleInputBuffer(out)
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    // MARK: - Buffer handler

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Buffers arrive already in targetFormat (16 kHz mono Float32).
        let rms = Self.rms(of: buffer)
        if let levelHandler { levelHandler(rms) }

        lock.lock()
        let isCapturing = capturing
        lock.unlock()
        guard isCapturing,
              let channelPtr = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
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
        for i in 0..<frames { let s = ptr[i]; sum += s * s }
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
