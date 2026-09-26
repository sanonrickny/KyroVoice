import Foundation
import AppKit
import ApplicationServices

/// Runnable check for the typing injector: every character reaches the window
/// server intact, in order, carrying no modifier flags, and the clipboard is
/// never touched.
///
/// It reads back its own key events through a listen-only event tap rather
/// than typing into a window. A menu-bar app cannot take keyboard focus on
/// macOS 26 (`activate(ignoringOtherApps:)` no-ops), so there is no text field
/// to read. This checks what KyroVoice posts, not what a given app does with
/// it: apps that read the virtual key code instead of the Unicode string still
/// need the Pasteboard strategy, and only a real app can show that.
///
/// Posting key events needs Accessibility, which macOS grants to the bundle
/// and not to a terminal, so launch it through LaunchServices:
///
///     open -n -W --stdout /tmp/typing.out --stderr /tmp/typing.out \
///         -a /Applications/KyroVoice.app --args --typing-check
///
/// ponytail: one event tap, one sample string, no framework. Typing on the
/// real keyboard while it runs lands in the same stream and fails the check.
/// Written only by the tap callback (a C function pointer, so it cannot close
/// over anything) and read after the events have drained.
private nonisolated(unsafe) var captured = ""
private nonisolated(unsafe) var sawModifiers = false

@MainActor
enum TypingCheck {

    static func run() {
        guard AXIsProcessTrusted() else {
            print("typing-check: ABORT, KyroVoice lacks Accessibility permission")
            exit(2)
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 64)
                event.keyboardGetUnicodeString(maxStringLength: 64, actualStringLength: &length, unicodeString: &buffer)
                if length > 0 {
                    captured += String(utf16CodeUnits: buffer, count: length)
                    if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty {
                        sawModifiers = true
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            print("typing-check: ABORT, could not create the event tap")
            exit(2)
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let sample = "Hi Marcus, the café meeting is at 9:30 👍🏽 (naïve résumé, 100% sure). "
            + String(repeating: "This longer passage checks that chunks arrive in order. ", count: 8)

        let clipboardBefore = NSPasteboard.general.changeCount
        let start = ContinuousClock.now
        do {
            try ClipboardInjector(strategy: .typing).typeInject(sample)
        } catch {
            print("typing-check: FAIL, \(error.localizedDescription)")
            exit(1)
        }
        let posted = ContinuousClock.now - start
        pump(2.0)

        var failures = 0
        func expect(_ condition: Bool, _ what: String, detail: String = "") {
            if condition {
                print("  ok    \(what)")
            } else {
                failures += 1
                print("  FAIL  \(what)\(detail.isEmpty ? "" : "\n        \(detail)")")
            }
        }

        print("typing-check: \(sample.count) characters posted in \(posted.kvMilliseconds) ms")
        expect(captured == sample, "every character arrived, in order",
               detail: "got: \(captured)")
        expect(!sawModifiers, "no modifier flags on the typed events")
        expect(NSPasteboard.general.changeCount == clipboardBefore, "clipboard untouched")

        print(failures == 0 ? "typing-check passed" : "typing-check: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
