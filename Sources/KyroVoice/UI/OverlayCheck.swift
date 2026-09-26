import Foundation
import AppKit

/// Runnable check for the one rule the HUD has to obey: whenever the phase is
/// not `.hidden`, the panel is on screen.
///
/// Every "the pebble did not show up" report traces back to a phase change that
/// nobody paired with a `show()`, or to a pending hide that fired into a new
/// session. Both are sequences, not pixels, so they are checkable without a
/// microphone, a hotkey or a human.
///
/// ponytail: asserts and a counter, no test framework. Run with `--overlay-check`.
@MainActor
enum OverlayCheck {

    static func run() {
        NSApp.setActivationPolicy(.accessory)

        let state = OverlayState()
        let overlay = FloatingOverlay(state: state)
        var failures = 0

        func expect(_ visible: Bool, _ what: String) {
            pump(0.25)
            let actual = overlay.isPanelVisible
            if actual == visible {
                print("  ok    \(what) [visible=\(actual)]")
            } else {
                failures += 1
                print("  FAIL  \(what) [expected visible=\(visible), got \(actual)]")
            }
        }

        print("overlay-check: phase drives visibility")

        // 1. The ordinary run: listening, processing, injected, gone.
        state.phase = .listening
        expect(true, "listening shows the panel")

        state.phase = .processing
        expect(true, "processing keeps it up")

        state.phase = .injected
        expect(true, "injected keeps it up")

        state.phase = .hidden
        expect(false, "hidden takes it down")

        // 2. A phase set while the panel is down must bring it back by itself.
        //    `stopAndTranscribe` sets `.processing` and never calls `show()`, so
        //    any session that starts with the panel down used to stay invisible
        //    for its whole life.
        state.phase = .processing
        expect(true, "processing from hidden re-shows without an explicit show()")
        state.phase = .hidden
        expect(false, "back down")

        state.phase = .error("mic is on fire")
        expect(true, "error from hidden re-shows")
        state.phase = .hidden
        expect(false, "back down")

        // 3. A pending hide must not eat the next session.
        state.phase = .injected
        overlay.scheduleHide(after: 0.3)
        pump(0.1)
        state.phase = .listening
        pump(0.5)               // the old hide deadline passes here
        expect(true, "a new listening phase cancels the pending hide")

        state.phase = .hidden
        expect(false, "teardown")

        // 4. Repeat sessions back to back, the way a user actually dictates.
        for i in 1...3 {
            state.phase = .listening
            expect(true, "session \(i) listening")
            state.phase = .processing
            state.phase = .injected
            overlay.scheduleHide(after: 0.2)
            pump(0.4)
            expect(false, "session \(i) hid itself")
        }

        // 5. Geometry and level, the other half of "it did not show up": a
        //    panel can be `isVisible` and still be parked off screen or buried
        //    under the Dock, which owns level 20.
        state.phase = .listening
        pump(0.25)
        if let frame = overlay.panelFrame, let screen = NSScreen.main {
            let inside = screen.visibleFrame.contains(frame)
            print(inside ? "  ok    panel sits inside the visible frame \(frame)"
                         : "  FAIL  panel is outside the visible frame \(frame) vs \(screen.visibleFrame)")
            if !inside { failures += 1 }
        } else {
            failures += 1
            print("  FAIL  no panel frame to check")
        }

        let level = overlay.panelLevel
        let dock = Int(CGWindowLevelForKey(.dockWindow))
        if level > dock {
            print("  ok    panel level \(level) clears the Dock at \(dock)")
        } else {
            failures += 1
            print("  FAIL  panel level \(level) is under the Dock at \(dock)")
        }

        // The window server's own answer, not AppKit's bookkeeping.
        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == getpid() }
        if onScreen.isEmpty {
            failures += 1
            print("  FAIL  the window server has no on-screen window for us")
        } else {
            print("  ok    window server lists it on screen \(onScreen.compactMap { $0[kCGWindowBounds as String] })")
        }
        state.phase = .hidden
        pump(0.2)

        print(failures == 0
              ? "overlay-check: PASS"
              : "overlay-check: FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    /// The panel is ordered in and out by AppKit and the hides are timers, so
    /// the run loop has to actually turn between assertions.
    private static func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
