import Foundation
import AppKit
import SwiftUI

/// Renders the app's own windows to PNG for the docs site.
///
/// `screencapture` needs the Screen Recording TCC grant, which a build machine
/// often does not have. This does not: the app draws its own view hierarchy
/// into a bitmap with `cacheDisplay(in:to:)`, so the pixels are the real UI,
/// just written to a file instead of the window server.
///
/// ponytail: only ever called from `--snapshot`, so no CLI parsing beyond the
/// directory argument and no options. Add a size flag when a second caller wants one.
@MainActor
enum UISnapshot {

    static func run(into directory: String) {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        NSApp.setActivationPolicy(.accessory)

        // The docs site is dark, so shoot the UI dark.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // The Models pane, not General: it is the one that shows both Parakeet
        // variants and their download state.
        capture(
            SettingsView(section: .models)
                .environmentObject(SettingsStore.shared)
                .environmentObject(PermissionsHolder.shared.service),
            size: NSSize(width: 620, height: 300),
            title: "KyroVoice",
            chrome: true,
            to: dir.appendingPathComponent("settings.png")
        )

        capture(
            HistoryView().environmentObject(HistoryStore(sample: sampleHistory)),
            size: NSSize(width: 460, height: 396),
            title: "Dictation History",
            chrome: true,
            to: dir.appendingPathComponent("history.png")
        )

        let listening = OverlayState()
        listening.phase = .listening
        listening.audioLevel = 0.72
        capture(
            OverlayView(state: listening),
            size: NSSize(width: 260, height: 36),
            title: nil,
            chrome: false,
            to: dir.appendingPathComponent("overlay.png")
        )

        let injected = OverlayState()
        injected.phase = .injected
        capture(
            OverlayView(state: injected),
            size: NSSize(width: 260, height: 36),
            title: nil,
            chrome: false,
            to: dir.appendingPathComponent("overlay-injected.png")
        )

        print("UISnapshot: wrote PNGs to \(dir.path)")
        exit(0)
    }

    /// Hosts `view` in a real window and asks that window to draw itself into a
    /// bitmap. `chrome: true` captures the theme frame too, so the title bar and
    /// traffic lights are the real ones rather than something drawn in CSS.
    private static func capture<V: View>(
        _ view: V, size: NSSize, title: String?, chrome: Bool, to url: URL
    ) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: chrome ? [.titled, .closable, .miniaturizable] : [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        if let title { window.title = title }
        if !chrome {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }
        // Key windows draw active title bars and focus rings; an unactivated
        // accessory app renders every control in its inactive gray.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // SwiftUI lays out on the next run loop pass, and async content (the
        // permissions probes) settles a beat later. Capturing immediately
        // produced a blank sheet.
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))

        let target: NSView = chrome ? (host.superview ?? host) : host
        target.layoutSubtreeIfNeeded()

        // cacheDisplay would inherit the window's backing scale, which is 1 on a
        // non-retina display and leaves the docs images soft. Draw into a bitmap
        // sized 2x instead: `rep.size` in points with 2x the pixels is what makes
        // the graphics context scale up.
        let bounds = target.bounds
        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width) * scale,
            pixelsHigh: Int(bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            print("UISnapshot: no bitmap for \(url.lastPathComponent)")
            return
        }
        rep.size = bounds.size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        target.displayIgnoringOpacity(bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("UISnapshot: no PNG for \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("UISnapshot: \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        window.orderOut(nil)
    }

    /// Synthetic rows. The real store holds the user's own dictation, which has
    /// no business being published.
    private static var sampleHistory: [HistoryEntry] {
        [
            ("The build is green and we ship on Friday.", DictationMode.normal, "Notes", 240.0),
            ("let x = foo(bar);", .code, "Visual Studio Code", 1_500.0),
            ("Hi Rob, I have attached the three files you asked for.", .email, "Mail", 4_200.0)
        ].map { text, mode, app, ago in
            HistoryEntry(
                id: UUID(),
                timestamp: Date().addingTimeInterval(-ago),
                text: text,
                mode: mode,
                targetAppName: app
            )
        }
    }
}
