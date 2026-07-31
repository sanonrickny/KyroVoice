import Foundation
import AVFoundation
import AppKit
import KyroVoiceObjC

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case engineStartFailed(underlying: Error)
    case formatUnavailable
    case noInputDevice
    case notReady

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access denied. Open System Settings → Privacy & Security → Microphone and enable KyroVoice."
        case .engineStartFailed(let e):
            return "Audio engine failed to start: \(e.localizedDescription)"
        case .formatUnavailable:
            return "Could not prepare 16 kHz mono Float32 audio format."
        case .noInputDevice:
            return "No audio input device available. Check your microphone connection and try again."
        case .notReady:
            return "Audio engine is still initialising. Please try again in a moment."
        }
    }
}

/// Captures default-input audio and produces 16 kHz mono Float32 PCM
/// suitable for Parakeet.
///
/// A fresh `AVAudioEngine` is built for every recording and torn down at the
/// end of it. That is deliberate. A long-lived engine caches a hidden
/// aggregate audio device and a stale output-bus format that macOS provides no
/// supported way to refresh; once sleep/wake, a Bluetooth switch or a
/// `coreaudiod` restart invalidates them, `installTapOnBus:` raises an
/// NSException on every subsequent attempt and the process aborts. That is
/// exactly the multi-day-uptime crash this app was dying from. Engine
/// construction costs ~10-50 ms, hidden under hotkey-down latency.
@MainActor
public final class AudioRecorder {
    public typealias LevelHandler = @Sendable (Float) -> Void

    public enum State { case idle, preparing, ready, recording, denied }

    public private(set) var state: State = .idle

    public nonisolated static let targetSampleRate: Double = 16_000

    /// ~200 ms at 48 kHz. The documented supported range for a tap is
    /// [100, 400] ms; the old 4096 (85 ms) was below the floor and silently
    /// clamped by AVAudioEngine anyway.
    private static let tapBufferSize: AVAudioFrameCount = 9600

    private var engine: AVAudioEngine?
    private var targetFormat: AVAudioFormat?

    /// Guards the fields below, which the audio render thread touches.
    /// They are `nonisolated(unsafe)` because `lock` provides the exclusion the
    /// main actor otherwise would.
    private nonisolated let lock = NSLock()
    private nonisolated(unsafe) var capturing = false
    private nonisolated(unsafe) var samples: [Float] = []
    private nonisolated(unsafe) var levelHandler: LevelHandler?
    private nonisolated(unsafe) var converter: AVAudioConverter?

    public init() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Settable from any thread; the tap callback reads it under `lock`.
    public nonisolated func setLevelHandler(_ handler: LevelHandler?) {
        lock.lock(); defer { lock.unlock() }
        levelHandler = handler
    }

    /// Sync accessors so async contexts never take `lock` directly.
    private nonisolated func isCapturing() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return capturing
    }

    private nonisolated func resetConverter() {
        lock.lock(); defer { lock.unlock() }
        converter = nil
    }

    // MARK: - Lifecycle

    /// Requests microphone access and builds the target format. Deliberately
    /// does NOT create an engine: anything built here would be stale by the
    /// time the user actually dictates.
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
        state = .ready
    }

    // MARK: - Capture control

    public func start() throws {
        switch state {
        case .ready, .idle: break
        case .denied:    throw AudioRecorderError.microphoneDenied
        case .preparing: throw AudioRecorderError.notReady
        case .recording: return
        }

        // No target format means prepare() has not succeeded yet; saying
        // "still initialising" is truer than "format unavailable".
        guard let targetFmt = targetFormat else { throw AudioRecorderError.notReady }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate) * 60)
        converter = nil
        capturing = true
        lock.unlock()

        do {
            try beginCapture(targetFmt: targetFmt)
        } catch {
            lock.lock(); capturing = false; lock.unlock()
            teardownEngine()
            throw error
        }

        state = .recording
    }

    private func beginCapture(targetFmt: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        self.engine = engine

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        let input = engine.inputNode

        // `format: nil` makes installTap use the node's *output* format, so
        // that is the format the tap will actually deliver and the one that
        // must be valid. Validating inputFormat instead (what this code used to
        // do) checks a value the tap never consults, which is why the guard
        // never prevented the crash.
        let outFmt = input.outputFormat(forBus: 0)
        let inFmt = input.inputFormat(forBus: 0)
        guard outFmt.sampleRate > 0, outFmt.channelCount > 0,
              inFmt.sampleRate > 0, inFmt.channelCount > 0,
              outFmt.sampleRate == inFmt.sampleRate else {
            NSLog("KyroVoice: rejecting tap — in=\(inFmt.sampleRate)Hz/\(inFmt.channelCount)ch out=\(outFmt.sampleRate)Hz/\(outFmt.channelCount)ch")
            throw AudioRecorderError.noInputDevice
        }

        do {
            try KVAudioEngineHelper.start(engine)
        } catch {
            throw AudioRecorderError.engineStartFailed(underlying: error)
        }

        do {
            // The installTapOnBus: call itself lives in Objective-C: an
            // NSException must never unwind through a Swift frame.
            try KVAudioEngineHelper.installTap(
                on: input,
                bus: 0,
                bufferSize: Self.tapBufferSize,
                format: nil
            ) { [weak self] buf, _ in
                self?.convertAndHandle(buf, targetFmt: targetFmt)
            }
        } catch {
            // The reason string is the entire diagnosis if this ever recurs.
            NSLog("KyroVoice: \(error.localizedDescription) — in=\(inFmt.sampleRate)Hz/\(inFmt.channelCount)ch out=\(outFmt.sampleRate)Hz/\(outFmt.channelCount)ch")
            engine.stop()
            throw error
        }
    }

    public func stop() -> [Float] {
        lock.lock()
        capturing = false
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        converter = nil
        lock.unlock()

        teardownEngine()

        if state == .recording { state = .ready }
        return captured
    }

    private func teardownEngine() {
        guard let engine else { return }
        NotificationCenter.default.removeObserver(
            self, name: .AVAudioEngineConfigurationChange, object: engine
        )
        KVAudioEngineHelper.removeTap(on: engine.inputNode, bus: 0)
        engine.stop()
        self.engine = nil
    }

    @objc private nonisolated func handleConfigChange() {
        // AVAudioEngineConfigurationChange arrives on an arbitrary thread, and
        // the engine must not be deallocated inside the handler. Hopping to the
        // main actor satisfies both.
        Task { @MainActor [weak self] in
            guard let self, self.isCapturing(),
                  let engine = self.engine,
                  let targetFmt = self.targetFormat else { return }

            KVAudioEngineHelper.removeTap(on: engine.inputNode, bus: 0)
            engine.stop()
            self.resetConverter()

            let input = engine.inputNode
            let outFmt = input.outputFormat(forBus: 0)
            guard outFmt.sampleRate > 0, outFmt.channelCount > 0 else {
                NSLog("KyroVoice: input device gone after config change")
                return
            }
            do {
                try KVAudioEngineHelper.start(engine)
                try KVAudioEngineHelper.installTap(
                    on: input, bus: 0, bufferSize: Self.tapBufferSize, format: nil
                ) { [weak self] buf, _ in
                    self?.convertAndHandle(buf, targetFmt: targetFmt)
                }
            } catch {
                NSLog("KyroVoice: audio reconfigure failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Conversion

    private nonisolated func convertAndHandle(_ buffer: AVAudioPCMBuffer,
                                              targetFmt: AVAudioFormat) {
        // The converter is built from the format the buffers actually arrive
        // in, and rebuilt if that format changes under a live tap. Allocating
        // here is not real-time safe, but it only happens on the first buffer
        // and on an actual device change.
        lock.lock()
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFmt)
        }
        let conv = converter
        lock.unlock()
        guard let conv else { return }

        let ratio = targetFmt.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFmt, frameCapacity: cap) else { return }
        var fed = false
        let status = conv.convert(to: out, error: nil) { _, flag in
            if fed { flag.pointee = .noDataNow; return nil }
            fed = true; flag.pointee = .haveData; return buffer
        }
        guard status != .error else { return }
        handleInputBuffer(out)
    }

    // MARK: - Buffer handler

    private nonisolated func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Buffers arrive already in targetFormat (16 kHz mono Float32).
        let rms = Self.rms(of: buffer)

        lock.lock()
        let handler = levelHandler
        let isCapturing = capturing
        lock.unlock()
        // Called outside the lock: the handler hops to the main actor and must
        // never run with the audio thread's lock held.
        handler?(rms)

        guard isCapturing,
              let channelPtr = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        lock.lock()
        // Cap the buffer so a forgotten toggle-mode recording can't grow
        // memory without bound (10 min ≈ 38 MB at 16 kHz Float32).
        if samples.count < Int(Self.targetSampleRate) * 600 {
            samples.append(contentsOf: UnsafeBufferPointer(start: channelPtr, count: count))
        }
        lock.unlock()
    }

    // MARK: - Helpers

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let ptr = channels[0]
        var sum: Float = 0
        for i in 0..<frames { let s = ptr[i]; sum += s * s }
        let mean = sum / Float(frames)
        // A non-finite sample would poison the overlay's adaptive normalizer
        // for the rest of the session.
        return mean.isFinite ? mean.squareRoot() : 0
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
