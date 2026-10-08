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
/// exactly the multi-day-uptime crash this app was dying from.
///
/// A cold start loses the start of speech: measured on the built-in mic, the
/// first sample lands 90-150 ms after the press and the next ~140 ms are
/// silence while the mic powers up, so "Use sub-agents" came out as "So
/// agents". With `keepReady` the engine instead stays running between
/// recordings and the last `preRoll` seconds before the press are kept. That
/// engine is still disposable: it is dropped on sleep and on any configuration
/// change and rebuilt fresh, never reused, so the crash above cannot recur.
@MainActor
public final class AudioRecorder {
    public typealias LevelHandler = @Sendable (Float) -> Void

    public enum State { case idle, preparing, ready, recording, denied }

    public private(set) var state: State = .idle

    public nonisolated static let targetSampleRate: Double = 16_000

    /// Audio kept from before the press, so a word started together with the
    /// hotkey is whole.
    public nonisolated static let preRoll: TimeInterval = 0.4

    /// Keep the microphone running between recordings so a press starts
    /// capturing instantly, with `preRoll` of audio from before it. Turns the
    /// system microphone indicator on while idle. Ignored for Bluetooth input:
    /// holding a headset mic open drops its playback to call quality.
    public var keepReady = false {
        didSet { refreshStandby() }
    }

    /// 100 ms of audio, the floor of the documented [100, 400] ms tap range.
    /// macOS honours the request, and the buffer in flight when recording stops
    /// is lost, so a smaller buffer loses less of the last word. Measured: 9600
    /// frames at 48 kHz arrived every 200 ms.
    private static func tapBufferSize(for format: AVAudioFormat) -> AVAudioFrameCount {
        AVAudioFrameCount(format.sampleRate / 10)
    }

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
    /// Host-clock seconds at the end of the newest captured buffer.
    private nonisolated(unsafe) var capturedEnd: TimeInterval = 0
    /// Host-clock seconds of the first captured sample in this recording.
    private nonisolated(unsafe) var capturedStart: TimeInterval = 0

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

    /// Host-clock seconds, the clock `capturedThrough()` is measured in.
    public nonisolated static func hostNow() -> TimeInterval {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    /// Host time up to which audio has been captured in this recording.
    public nonisolated func capturedThrough() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return capturedEnd
    }

    /// Host time of the first sample in this recording, 0 before any audio.
    public nonisolated func capturedFrom() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return capturedStart
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
        refreshStandby()
    }

    // MARK: - Standby

    /// Starts or stops the idle engine to match `keepReady` and the current
    /// input device. Never touches a recording in progress.
    public func refreshStandby() {
        guard state == .ready, let targetFmt = targetFormat else { return }
        if keepReady, !Self.defaultInputIsBluetooth() {
            guard engine == nil else { return }
            do {
                try startEngine(targetFmt: targetFmt)
                NSLog("KyroVoice: microphone standby on")
            } catch {
                // Not fatal: start() falls back to a cold engine per press.
                NSLog("KyroVoice: standby failed, presses will cold-start: \(error.localizedDescription)")
                teardownEngine()
            }
        } else if engine != nil {
            teardownEngine()
            NSLog("KyroVoice: microphone standby off")
        }
    }

    /// Drops the idle engine before sleep. Wake brings back a new device
    /// state, which a pre-sleep engine would carry stale.
    public func suspendStandby() {
        guard state == .ready else { return }
        teardownEngine()
    }

    /// The standby engine is usable if a buffer arrived recently. A stalled
    /// tap (device unplugged with no notification) fails this and the press
    /// rebuilds from scratch.
    private func standbyIsLive() -> Bool {
        engine != nil && Self.hostNow() - capturedThrough() < 0.5
    }

    private nonisolated static func defaultInputIsBluetooth() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr
        else { return false }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Loads the input device's audio unit once, off the main thread, and
    /// throws the engine away. The first `start()` otherwise pays that cold
    /// cost on the main thread: measured 335 ms to 3 s on the first press vs
    /// ~200 ms after. No capture runs, so the mic indicator stays off, and no
    /// engine is kept alive (see the type comment for why that matters).
    public nonisolated static func prewarmInputDevice() {
        Thread.detachNewThread {
            // Held in a local: `AVAudioEngine().inputNode` frees the engine
            // before the node is used and crashes.
            let engine = AVAudioEngine()
            _ = engine.inputNode.outputFormat(forBus: 0)
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

        // No target format means prepare() has not succeeded yet; saying
        // "still initialising" is truer than "format unavailable".
        guard let targetFmt = targetFormat else { throw AudioRecorderError.notReady }

        if standbyIsLive() {
            // The ring already holds the pre-roll: keep it and start appending.
            lock.lock()
            capturedStart = capturedEnd - Double(samples.count) / Self.targetSampleRate
            capturing = true
            lock.unlock()
            state = .recording
            return
        }

        // Cold path: standby is off, Bluetooth, or its engine stalled.
        teardownEngine()
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate) * 60)
        converter = nil
        capturedEnd = 0
        capturedStart = 0
        capturing = true
        lock.unlock()

        do {
            try startEngine(targetFmt: targetFmt)
        } catch {
            lock.lock(); capturing = false; lock.unlock()
            teardownEngine()
            throw error
        }

        state = .recording
    }

    private func startEngine(targetFmt: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        self.engine = engine

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange(_:)),
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
                bufferSize: Self.tapBufferSize(for: outFmt),
                format: nil
            ) { [weak self] buf, when in
                self?.convertAndHandle(buf, at: when, targetFmt: targetFmt)
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
        // Cleared, not kept as pre-roll: the next press must not replay the
        // end of this dictation.
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        if state == .recording { state = .ready }
        // A cold-started engine becomes the standby one, if standby is wanted.
        if !keepReady || Self.defaultInputIsBluetooth() { teardownEngine() }
        refreshStandby()
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
        resetConverter()
    }

    @objc private nonisolated func handleConfigChange(_ note: Notification) {
        // AVAudioEngineConfigurationChange arrives on an arbitrary thread, and
        // the engine must not be deallocated inside the handler. Hopping to the
        // main actor satisfies both.
        let changed = note.object as AnyObject?
        Task { @MainActor [weak self] in
            // A notification from an engine already replaced is stale.
            guard let self, let engine = self.engine, engine === changed,
                  let targetFmt = self.targetFormat else { return }

            // Rebuild rather than restart: a restarted engine keeps the stale
            // device state that made installTapOnBus: throw.
            self.teardownEngine()
            guard self.isCapturing() else {
                self.refreshStandby()  // also re-checks for a Bluetooth device
                return
            }
            do {
                try self.startEngine(targetFmt: targetFmt)
            } catch {
                NSLog("KyroVoice: audio reconfigure failed: \(error.localizedDescription)")
                self.teardownEngine()
            }
        }
    }

    // MARK: - Conversion

    private nonisolated func convertAndHandle(_ buffer: AVAudioPCMBuffer,
                                              at when: AVAudioTime,
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
        let end = when.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: when.hostTime) + Double(buffer.frameLength) / buffer.format.sampleRate
            : Self.hostNow()
        handleInputBuffer(out, end: end)
    }

    // MARK: - Buffer handler

    private nonisolated func handleInputBuffer(_ buffer: AVAudioPCMBuffer, end: TimeInterval) {
        // Buffers arrive already in targetFormat (16 kHz mono Float32).
        let rms = Self.rms(of: buffer)

        lock.lock()
        let handler = capturing ? levelHandler : nil
        lock.unlock()
        // Called outside the lock: the handler hops to the main actor and must
        // never run with the audio thread's lock held.
        handler?(rms)

        guard let channelPtr = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        lock.lock()
        // Cap the buffer so a forgotten toggle-mode recording can't grow
        // memory without bound (10 min ≈ 38 MB at 16 kHz Float32).
        if samples.count < Int(Self.targetSampleRate) * 600 {
            samples.append(contentsOf: UnsafeBufferPointer(start: channelPtr, count: count))
        }
        if !capturing {
            // Standby: keep only the pre-roll.
            // ponytail: removeFirst shifts ~8k floats per 100 ms buffer; a real
            // ring buffer if preRoll ever grows to seconds.
            let excess = samples.count - Int(Self.preRoll * Self.targetSampleRate)
            if excess > 0 { samples.removeFirst(excess) }
        }
        if capturedStart == 0 { capturedStart = end - Double(count) / Self.targetSampleRate }
        capturedEnd = end
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
