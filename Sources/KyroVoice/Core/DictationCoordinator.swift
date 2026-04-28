import Foundation
import AppKit
import Combine

/// Central pipeline:
///   hotkey-down → recorder.start
///   hotkey-up   → recorder.stop → whisper → processor → injector
@MainActor
public final class DictationCoordinator: ObservableObject {
    @Published public private(set) var isRecording: Bool = false

    private let settings: SettingsStore
    private let recorder: AudioRecorder
    private let whisper: WhisperEngine
    private let processor: TextProcessor
    private let injector: ClipboardInjector
    private let modeResolver: ModeResolver
    private let overlayState: OverlayState
    private let overlay: FloatingOverlay

    private var transcribeTask: Task<Void, Never>?

    public init(
        settings: SettingsStore,
        recorder: AudioRecorder,
        whisper: WhisperEngine,
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

        recorder.levelHandler = { [weak self] rms in
            Task { @MainActor in
                self?.overlayState.pushLevel(rms)
            }
        }
    }

    // MARK: - Hotkey entry points

    public func hotkeyPressed() {
        switch settings.hotkeyMode {
        case .pushToTalk:
            startRecording()
        case .toggle:
            if isRecording { stopAndTranscribe() } else { startRecording() }
        }
    }

    public func hotkeyReleased() {
        switch settings.hotkeyMode {
        case .pushToTalk:
            if isRecording { stopAndTranscribe() }
        case .toggle:
            break
        }
    }

    public func userToggle() async {
        if isRecording { stopAndTranscribe() } else { startRecording() }
    }

    public func modelChanged(to variant: ModelVariant) async {
        await whisper.setVariant(variant)
        Task.detached(priority: .utility) { [whisper] in
            try? await whisper.warmUp()
        }
    }

    // MARK: - Pipeline

    private func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            overlayState.resetLevels()
            overlayState.phase = .listening
            overlay.show()
        } catch {
            showError(error.localizedDescription, durationSeconds: 3)
        }
    }

    private func stopAndTranscribe() {
        guard isRecording else { return }
        let samples = recorder.stop()
        isRecording = false
        overlayState.phase = .processing

        // Resolve at stop so the user's current frontmost app wins.
        let resolvedMode = modeResolver.resolve(default: settings.mode)
        let cloud = settings.cloudCleanupEnabled

        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.whisper.transcribe(samples: samples)
                let cleaned: String
                if cloud {
                    cleaned = try await self.processor.processAsync(raw, mode: resolvedMode, useCloud: true)
                } else {
                    cleaned = self.processor.process(raw, mode: resolvedMode)
                }
                guard !Task.isCancelled else { return }
                guard !cleaned.isEmpty else {
                    self.showError("No speech detected.", durationSeconds: 2.5)
                    return
                }
                try await self.injector.inject(cleaned)
                self.overlayState.phase = .injected
                self.overlay.scheduleHide(after: 2.5)
            } catch {
                self.showError(error.localizedDescription, durationSeconds: 3.5)
            }
        }
    }

    private func showError(_ message: String, durationSeconds: TimeInterval) {
        overlayState.phase = .error(message)
        overlay.show()
        overlay.scheduleHide(after: durationSeconds)
    }
}
