import Foundation
import AppKit
import Combine

/// Central pipeline:
///   hotkey-down → recorder.start
///   hotkey-up   → recorder.stop → speech → processor → injector
@MainActor
public final class DictationCoordinator: ObservableObject {
    @Published public private(set) var isRecording: Bool = false

    private let settings: SettingsStore
    private let recorder: AudioRecorder
    private let whisper: SpeechEngine
    private let processor: TextProcessor
    private let injector: ClipboardInjector
    private let modeResolver: ModeResolver
    private let overlayState: OverlayState
    private let overlay: FloatingOverlay

    private var transcribeTask: Task<Void, Never>?
    /// Pending end of a recording: it keeps capturing for `tailCapture` after
    /// release, so the last word isn't cut off.
    private var tailTask: Task<Void, Never>?
    private var releasedAt: ContinuousClock.Instant?
    /// People tend to release the key while still saying the last word.
    private static let tailCapture: TimeInterval = 0.15
    private var targetPID: pid_t = 0
    private var cancellables = Set<AnyCancellable>()

    public init(
        settings: SettingsStore,
        recorder: AudioRecorder,
        whisper: SpeechEngine,
        processor: TextProcessor,
        injector: ClipboardInjector,
        modeResolver: ModeResolver,
        overlayState: OverlayState,
        overlay: FloatingOverlay
    ) {
        self.settings     = settings
        self.recorder     = recorder
        self.whisper      = whisper
        self.processor    = processor
        self.injector     = injector
        self.modeResolver = modeResolver
        self.overlayState = overlayState
        self.overlay      = overlay

        recorder.setLevelHandler { [weak overlayState] rms in
            Task { @MainActor in
                overlayState?.pushLevel(rms)
            }
        }

        // Keep SpeechEngine in sync when model is changed from SettingsView.
        settings.$model
            .dropFirst()
            .sink { [weak self] variant in
                guard let self else { return }
                Task { await self.modelChanged(to: variant) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey entry points

    public func hotkeyPressed() {
        NSLog("KyroVoice: hotkeyPressed — mode=\(settings.hotkeyMode.rawValue) isRecording=\(isRecording)")
        switch settings.hotkeyMode {
        case .pushToTalk:
            startRecording()
        case .toggle:
            if isRecording, tailTask == nil { stopAndTranscribe() } else { startRecording() }
        }
    }

    public func hotkeyReleased() {
        NSLog("KyroVoice: hotkeyReleased — isRecording=\(isRecording)")
        switch settings.hotkeyMode {
        case .pushToTalk:
            if isRecording { stopAndTranscribe() }
        case .toggle:
            break
        }
    }

    public func userToggle() async {
        if isRecording, tailTask == nil { stopAndTranscribe() } else { startRecording() }
    }

    public func modelChanged(to variant: ModelVariant) async {
        await whisper.setVariant(variant)
        Task.detached(priority: .utility) { [whisper] in
            try? await whisper.warmUp()
        }
    }

    // MARK: - Pipeline

    private func startRecording() {
        if let tail = tailTask {
            // A press during the previous recording's tail ends that one now,
            // otherwise the new press would be swallowed. Its transcription
            // is kept: the user finished speaking it.
            tail.cancel()
            tailTask = nil
            finishRecording()
        } else {
            guard !isRecording else { return }
            // A transcription still running belongs to the previous press. Left
            // alone it finishes into this session's HUD.
            transcribeTask?.cancel()
        }
        // Capture target app PID now — before transcription delay shifts focus.
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        NSLog("KyroVoice: target PID=\(targetPID)")
        do {
            try recorder.start()
            isRecording = true
            overlayState.resetLevels()
            overlayState.phase = .listening
            NSLog("KyroVoice: recording started — recorderState=\(recorder.state)")
        } catch {
            NSLog("KyroVoice: startRecording failed — \(error.localizedDescription)")
            showError(error.localizedDescription, durationSeconds: 3)
        }
    }

    private func stopAndTranscribe() {
        guard isRecording, tailTask == nil else { return }
        releasedAt = ContinuousClock.now
        overlayState.phase = .processing
        // Stop once the recorder holds audio through release + tail. A fixed
        // sleep stopped mid-buffer: tap buffers land every ~100 ms and the one
        // in flight, the end of the last word, was dropped. The deadline
        // covers a tap that stops delivering.
        let target = AudioRecorder.hostNow() + Self.tailCapture
        let deadline = target + 0.2
        tailTask = Task { [weak self, recorder] in
            while recorder.capturedThrough() < target, AudioRecorder.hostNow() < deadline {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.tailTask = nil
            self.finishRecording()
        }
    }

    private func finishRecording() {
        guard isRecording else { return }
        let clock = ContinuousClock()
        let released = releasedAt ?? clock.now
        let tailDone = clock.now
        let samples = recorder.stop()
        isRecording = false
        NSLog("KyroVoice: stopped — \(samples.count) samples collected")

        guard !samples.isEmpty else {
            NSLog("KyroVoice: no samples, aborting")
            overlayState.phase = .hidden
            return
        }

        overlayState.phase = .processing

        // Resolve at stop so the user's current frontmost app wins.
        let resolvedMode = modeResolver.resolve(default: settings.mode)
        // Captured now: a press during transcription overwrites `targetPID`.
        let target = targetPID
        NSLog("KyroVoice: transcribing — mode=\(resolvedMode)")

        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let transcribeStart = clock.now
                let raw = try await self.whisper.transcribe(samples: samples)
                let transcribed = clock.now
                NSLog("KyroVoice: raw='\(raw)'")
                let cleaned = self.processor.process(raw, mode: resolvedMode)
                let processed = clock.now
                NSLog("KyroVoice: cleaned='\(cleaned)'")
                guard !Task.isCancelled else { return }
                guard !cleaned.isEmpty else {
                    NSLog("KyroVoice: cleaned text empty — showing 'No speech detected'")
                    self.showError("No speech detected.", durationSeconds: 2.5)
                    return
                }
                NSLog("KyroVoice: injecting via \(self.settings.injectionStrategy.rawValue) targetPID=\(target)")
                try await self.injector.inject(cleaned, targetPID: target)
                NSLog("KyroVoice: injection succeeded")
                NSLog("KyroVoice: timing audio=\(samples.count / 16) ms tail=\((tailDone - released).kvMilliseconds) stop=\((transcribeStart - tailDone).kvMilliseconds) speech=\((transcribed - transcribeStart).kvMilliseconds) text=\((processed - transcribed).kvMilliseconds) (paste lands ~30 ms later, see 'paste posted')")
                let appName = NSRunningApplication(processIdentifier: target)?.localizedName
                HistoryStore.shared.add(HistoryEntry(
                    id: UUID(),
                    timestamp: Date(),
                    text: cleaned,
                    mode: resolvedMode,
                    targetAppName: appName
                ))
                self.finish(.injected, hideAfter: 0.5)
            } catch {
                NSLog("KyroVoice: pipeline error — \(error.localizedDescription)")
                self.showError(error.localizedDescription, durationSeconds: 3.5)
            }
        }
    }

    private func showError(_ message: String, durationSeconds: TimeInterval) {
        finish(.error(message), hideAfter: durationSeconds)
    }

    /// Terminal HUD feedback for a dictation that just ended.
    ///
    /// A newer recording owns the pebble. Without this guard a slow
    /// transcription lands `.injected` plus a 0.5 s hide on top of a session
    /// that is already listening: the pebble vanishes mid-sentence and the rest
    /// of that dictation runs with the panel ordered out.
    private func finish(_ phase: OverlayState.Phase, hideAfter seconds: TimeInterval) {
        guard !isRecording else { return }
        overlayState.phase = phase
        overlay.scheduleHide(after: seconds)
    }
}

extension Duration {
    /// Whole milliseconds, for timing logs.
    var kvMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
