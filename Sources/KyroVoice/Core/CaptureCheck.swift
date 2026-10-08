import Foundation
import AppKit
import AVFoundation
import CoreAudio

/// Runnable check for "the first words of a dictation are missing".
///
/// 1. Lag: how much audio before (or after) the press a recording holds, cold
///    and with the standby microphone.
/// 2. Device churn: the default input switches to another device and back,
///    idle and mid-recording, and capture keeps working. A long-lived engine is
///    what crashed this app before, so the standby one must survive this.
/// 3. End to end: speech plays from the MacBook speakers starting exactly at
///    the press (and once 150 ms before it), and goes through the real
///    DictationCoordinator, Parakeet, TextProcessor and typing injector. The
///    typed text is swallowed by an event tap and its first words compared.
///    The cold run reproduces the bug and is reported, not asserted.
///
/// Needs the bundle's Microphone grant (and Accessibility for part 3), so
/// launch it through LaunchServices:
///
///     open -n -W --stdout /tmp/capture.out --stderr /tmp/capture.out \
///         -a .build/KyroVoice.app --args --capture-check [--audible]
///
/// Part 3 plays speech out loud, so it only runs with `--audible`.
/// ponytail: asserts and a counter, no framework. Briefly changes the default
/// input device (restored before exit).
private nonisolated(unsafe) var typed = ""

@MainActor
enum CaptureCheck {
    private static var failures = 0

    static func run() {
        Task { @MainActor in
            await checks()
            print(failures == 0 ? "\ncapture-check passed" : "\ncapture-check: \(failures) failure(s)")
            exit(failures == 0 ? 0 : 1)
        }
    }

    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL")  \(what)")
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func checks() async {
        let recorder = AudioRecorder()
        do { try await recorder.prepare() } catch {
            print("ABORT prepare: \(error.localizedDescription)"); exit(2)
        }

        print("1. audio held from before the press (negative = lost after it)")
        recorder.keepReady = false
        for _ in 0..<3 {
            let lead = await trial(recorder)
            print(String(format: "  info  cold     %+5.0f ms", lead * 1000))
        }
        recorder.keepReady = true
        await sleep(1)
        for _ in 0..<3 {
            let lead = await trial(recorder)
            expect(lead >= AudioRecorder.preRoll - 0.15,
                   String(format: "standby  %+5.0f ms of pre-roll", lead * 1000))
        }

        print("2. default input switches, idle and mid-recording")
        if let original = defaultInput(), let other = otherInput(than: original) {
            defer { setDefaultInput(original) }
            setDefaultInput(other)
            await sleep(1.5)
            setDefaultInput(original)
            await sleep(1.5)
            let lead = await trial(recorder)
            expect(lead >= AudioRecorder.preRoll - 0.15,
                   String(format: "standby recovers after an idle switch (%+.0f ms)", lead * 1000))

            try? recorder.start()
            await sleep(0.5)
            setDefaultInput(other)
            await sleep(1)
            setDefaultInput(original)
            await sleep(1)
            let through = recorder.capturedThrough()
            let samples = recorder.stop()
            expect(AudioRecorder.hostNow() - through < 0.5 && samples.count > 16_000,
                   "a recording keeps capturing across a switch (\(samples.count / 16) ms)")
            await sleep(1)
            let after = await trial(recorder)
            expect(after >= AudioRecorder.preRoll - 0.15, "standby live after that recording")
        } else {
            print("  skip  no second input device")
        }

        recorder.keepReady = false
        let cold = await trial(recorder)
        expect(cold < 0, "turning standby off goes back to a cold start")

        guard CommandLine.arguments.contains("--audible") else {
            print("3. skipped: pass --audible to play speech through the speakers")
            return
        }
        print("3. speech that starts with the press, through the whole pipeline")
        await endToEnd(recorder)
    }

    /// Seconds of audio the recording holds from before the press. Also
    /// fails if the samples do not fill the host-clock span they cover, which
    /// is what a dropout at the press would look like.
    private static func trial(_ recorder: AudioRecorder) async -> Double {
        await sleep(0.6)  // refill the pre-roll after the previous trial
        let press = AudioRecorder.hostNow()
        do { try recorder.start() } catch {
            print("  FAIL  start: \(error.localizedDescription)"); failures += 1; return -1
        }
        await sleep(0.4)
        let first = recorder.capturedFrom(), last = recorder.capturedThrough()
        let samples = recorder.stop()
        let gap = (last - first) - Double(samples.count) / AudioRecorder.targetSampleRate
        if abs(gap) > 0.03 {
            failures += 1
            print(String(format: "  FAIL  %.0f ms of audio missing inside the recording", gap * 1000))
        }
        return press - first
    }

    // MARK: - End to end

    private static func endToEnd(_ recorder: AudioRecorder) async {
        guard AXIsProcessTrusted() else {
            print("  FAIL  KyroVoice lacks Accessibility, cannot capture typed text"); failures += 1; return
        }
        guard let speakers = device(named: "MacBook Pro Speakers") else {
            print("  skip  no built-in speakers"); return
        }
        let whisper = SpeechEngine(variant: .parakeetV2)
        do { try await whisper.warmUp() } catch {
            print("  FAIL  model: \(error.localizedDescription)"); failures += 1; return
        }
        let state = OverlayState()
        let coordinator = DictationCoordinator(
            settings: .shared, recorder: recorder, whisper: whisper,
            processor: TextProcessor(), injector: ClipboardInjector(strategy: .typing),
            modeResolver: ModeResolver(), overlayState: state,
            overlay: FloatingOverlay(state: state), history: HistoryStore(sample: []))
        guard swallowTypedText() else {
            print("  FAIL  could not create the event tap"); failures += 1; return
        }
        let player = Player(device: speakers)

        let phrases = ["Use sub agents if needed.", "Please send the report to Marcus before Friday."]
        for ready in [false, true] {
            recorder.keepReady = ready
            await sleep(1.5)
            for phrase in phrases {
                for early in [0.0, 0.15] {
                    guard let speech = player.load(phrase) else {
                        print("  FAIL  say"); failures += 1; continue
                    }
                    typed = ""
                    player.play(speech)
                    await sleep(early)
                    press(coordinator)
                    await sleep(Double(speech.frameLength) / speech.format.sampleRate - early + 0.25)
                    release(coordinator)
                    for _ in 0..<60 where typed.isEmpty { await sleep(0.1) }
                    await sleep(0.3)
                    // First word only: speaker-to-mic playback turns "sub" into
                    // "of" now and then even with capture fully live.
                    let want = words(phrase).prefix(1), got = words(typed).prefix(1)
                    let label = "\(ready ? "standby" : "cold   ") speech \(early == 0 ? "at press  " : "150ms early") \"\(typed)\""
                    if ready { expect(got == want, label) } else { print("  \(got == want ? "info" : "LOST")  \(label)") }
                }
            }
        }
        player.stop()
    }

    private static func press(_ c: DictationCoordinator) { c.hotkeyPressed() }

    /// Toggle mode ends a recording with a second press, not a release.
    private static func release(_ c: DictationCoordinator) {
        if SettingsStore.shared.hotkeyMode == .pushToTalk { c.hotkeyReleased() } else { c.hotkeyPressed() }
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Drops every key event carrying text, recording it in `typed`, so the
    /// dictations never land in whatever app is frontmost.
    private static func swallowTypedText() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 64)
                event.keyboardGetUnicodeString(maxStringLength: 64, actualStringLength: &length, unicodeString: &buffer)
                guard length > 0, event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
                else { return Unmanaged.passUnretained(event) }
                if type == .keyDown { typed += String(utf16CodeUnits: buffer, count: length) }
                return nil
            },
            userInfo: nil
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Plays `say` output on a chosen device, leading silence trimmed so the
    /// first word starts at the first sample.
    private final class Player {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()

        init(device: AudioDeviceID) {
            var id = device
            if let unit = engine.outputNode.audioUnit {
                AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                     0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
            engine.attach(node)
        }

        func load(_ text: String) -> AVAudioPCMBuffer? {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("kv-capture.wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-v", "Alex", "-o", url.path, "--data-format=LEF32@22050", text]
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            guard let file = try? AVAudioFile(forReading: url),
                  let all = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: all)) != nil,
                  let data = all.floatChannelData?[0] else { return nil }
            let n = Int(all.frameLength)
            let onset = (0..<n).first { abs(data[$0]) > 0.02 } ?? 0
            guard let out = AVAudioPCMBuffer(pcmFormat: all.format, frameCapacity: AVAudioFrameCount(n - onset)) else { return nil }
            out.frameLength = AVAudioFrameCount(n - onset)
            out.floatChannelData![0].update(from: data + onset, count: n - onset)
            return out
        }

        func play(_ buffer: AVAudioPCMBuffer) {
            if !engine.isRunning {
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                try? engine.start()
            }
            node.scheduleBuffer(buffer)
            node.play()
        }

        func stop() { node.stop(); engine.stop() }
    }

    // MARK: - Core Audio devices

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                    _ initial: T) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func allDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    private static func device(named wanted: String) -> AudioDeviceID? {
        allDevices().first { name($0) == wanted }
    }

    private static func defaultInput() -> AudioDeviceID? {
        property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, AudioDeviceID(0))
    }

    /// Another device with input streams, preferring a virtual one so the
    /// switch is silent and needs no hardware.
    private static func otherInput(than current: AudioDeviceID) -> AudioDeviceID? {
        let inputs = allDevices().filter { id in
            guard id != current else { return false }
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                  mScope: kAudioObjectPropertyScopeInput,
                                                  mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
        }
        let virtual = inputs.first {
            property($0, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0)) == kAudioDeviceTransportTypeVirtual
        }
        return virtual ?? inputs.first
    }

    private static func setDefaultInput(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        print("  info  default input -> \(name(id))\(status == noErr ? "" : " FAILED \(status)")")
    }
}
