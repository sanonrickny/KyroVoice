import Foundation
import FluidAudio

// ponytail: one runnable end-to-end check for the Parakeet swap instead of a
// test target. Synthesises speech with `say`, feeds it through the real
// SpeechEngine, and asserts the transcript. Run with
// `./.build/release/KyroVoice --speech-check`. Downloads ~450 MB on first run.
enum SpeechEngineSelfCheck {
    /// Lowercase, strip everything that is not a letter, digit or space, so the
    /// comparison tests recognition rather than punctuation style.
    private static func normalize(_ s: String) -> String {
        let kept = s.lowercased().map { c -> Character in
            c.isLetter || c.isNumber || c.isWhitespace ? c : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private static func say(_ text: String, to url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // Alex is a fixed, always-installed voice, so the check does not drift
        // with whatever the user picked in System Settings.
        // WAV + little-endian float. AIFF is big-endian and silently rejects LEF32.
        p.arguments = ["-v", "Alex", "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "SpeechEngineSelfCheck", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "say failed"])
        }
    }

    static func run() async -> Never {
        let engine = SpeechEngine(variant: .parakeetV2)
        let converter = AudioConverter()
        let tmp = FileManager.default.temporaryDirectory
        var failures = 0

        print("loading parakeet v2 (downloads ~450 MB on first run)...")
        do {
            let t0 = Date()
            try await engine.warmUp()
            print("model ready in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        } catch {
            print("FAIL could not load model: \(error.localizedDescription)")
            exit(1)
        }

        let processor = TextProcessor()

        /// Speaks `spoken`, transcribes it, then runs the result through the
        /// real TextProcessor. Asserts on the processed text, because that is
        /// what actually gets injected. `want` defaults to `spoken`; pass it
        /// explicitly where Parakeet's inverse text normalization reshapes the
        /// words (spelled-out numbers become digits).
        func expect(_ spoken: String, want: String? = nil, line: UInt = #line) async {
            let url = tmp.appendingPathComponent("kv-check-\(line).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                try say(spoken, to: url)
                let samples = try converter.resampleAudioFile(path: url.path)
                let t0 = Date()
                let raw = try await engine.transcribe(samples: samples)
                let elapsed = Date().timeIntervalSince(t0)
                let audioSeconds = Double(samples.count) / 16_000
                let cleaned = processor.process(raw, mode: .normal)
                if normalize(cleaned) == normalize(want ?? spoken) {
                    print(String(format: "ok   %.2fs audio in %.2fs (%.0fx realtime)  \"\(cleaned)\"",
                                 audioSeconds, elapsed, audioSeconds / max(elapsed, 0.001)))
                } else {
                    failures += 1
                    print("FAIL (line \(line))")
                    print("   said:  \(spoken)")
                    print("   want:  \(want ?? spoken)")
                    print("   raw:   \(raw)")
                    print("   after: \(cleaned)")
                }
            } catch {
                failures += 1
                print("FAIL (line \(line)) \(error.localizedDescription)")
            }
        }

        await expect("The quick brown fox jumps over the lazy dog.")
        await expect("Send the quarterly report to Marcus before Friday afternoon.")
        // Digits and times. Parakeet writes numbers as digits, and the
        // PunctuationSpacer used to shred those into "9. 30" / "14 th".
        await expect("The meeting is at nine thirty on March fourteenth.",
                     want: "The meeting is at 9.30 on March 14th.")
        // Long-form: exercises the chunked encoder path past the 15s window.
        await expect("""
            This is a longer passage intended to push the recognizer past a \
            single encoder window so that the chunking and seam repair logic \
            actually runs instead of being skipped entirely by a short clip.
            """)

        // Silence must be rejected, not injected as empty text.
        do {
            _ = try await engine.transcribe(samples: [Float](repeating: 0, count: 16_000))
            failures += 1
            print("FAIL silent buffer should have thrown")
        } catch {
            print("ok   silent buffer rejected")
        }

        print(failures == 0 ? "\nspeech-check passed" : "\nspeech-check FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
