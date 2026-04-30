import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum InjectionError: Error, LocalizedError {
    case accessibilityDenied
    case inputMonitoringDenied
    case noFocusedElement
    case attributeUnsupported

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission required. System Settings → Privacy & Security → Accessibility → KyroVoice."
        case .inputMonitoringDenied:
            return "Input Monitoring permission required. System Settings → Privacy & Security → Input Monitoring → KyroVoice."
        case .noFocusedElement:
            return "No focused text field detected."
        case .attributeUnsupported:
            return "This app doesn't expose its text via Accessibility."
        }
    }
}

/// Inserts text at the cursor in the frontmost app.
/// - Default: pasteboard + simulated ⌘V (works almost everywhere).
/// - AX: direct Accessibility insertion (works in Cocoa apps but unreliable in Electron/web).
public final class ClipboardInjector {
    /// Kept in sync with `SettingsStore.injectionStrategy` (see `AppDelegate`).
    private var strategy: InjectionStrategyKind
    private let restoreDelay: TimeInterval

    public init(strategy: InjectionStrategyKind = .pasteboard, restoreDelay: TimeInterval = 0.40) {
        self.strategy = strategy
        self.restoreDelay = restoreDelay
    }

    public func setStrategy(_ strategy: InjectionStrategyKind) {
        self.strategy = strategy
    }

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func inject(_ text: String, targetPID: pid_t = 0) async throws {
        guard !text.isEmpty else { return }
        switch strategy {
        case .pasteboard:    try await pasteboardInject(text, targetPID: targetPID)
        case .accessibility: try axInject(text)
        case .auto:
            do { try axInject(text) }
            catch { try await pasteboardInject(text, targetPID: targetPID) }
        }
    }

    // MARK: - Pasteboard + Cmd+V

    private func pasteboardInject(_ text: String, targetPID: pid_t) async throws {
        let pb = NSPasteboard.general

        // Snapshot full pasteboard (all types) for restore.
        let snapshot = snapshotPasteboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // KyroVoice is an .accessory app with a .nonactivatingPanel overlay, so
        // the original app retains focus the entire time (recording + Whisper
        // transcription). No explicit activation is needed; cghidEventTap
        // routes the ⌘V to whichever window is currently key, which is the
        // original app.  (activate(options:) is deprecated on macOS 14+ and
        // silently no-ops on macOS 26, so removing it avoids a race where the
        // activation callback fires after we post the key event.)
        //
        // Give the pasteboard write time to propagate to the target process.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms

        try postCommandV()

        // Restore previous pasteboard contents after the paste settles.
        try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        restorePasteboard(pb, items: snapshot)
    }

    private func snapshotPasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pb.pasteboardItems else { return [] }
        var out: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            if !dict.isEmpty { out.append(dict) }
        }
        return out
    }

    private func restorePasteboard(_ pb: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        guard !items.isEmpty else { return }
        pb.clearContents()
        var newItems: [NSPasteboardItem] = []
        for itemDict in items {
            let item = NSPasteboardItem()
            for (type, data) in itemDict {
                item.setData(data, forType: type)
            }
            newItems.append(item)
        }
        pb.writeObjects(newItems)
    }

    private func postCommandV() throws {
        // hidSystemState reflects actual hardware key state, avoiding the stale
        // Cmd+Shift modifier that combinedSessionState inherits from the just-
        // released hotkey combo. Sending only VDown/VUp with .maskCommand is
        // sufficient — separate CmdDown/CmdUp events are unnecessary and can
        // confuse apps that have standalone Cmd key handlers.
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw InjectionError.inputMonitoringDenied
        }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            throw InjectionError.inputMonitoringDenied
        }
        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand

        // cghidEventTap routes through the macOS window server so the event
        // reaches the key window's focused responder. postToPid sends to the
        // process queue directly, bypassing window-server routing, so the event
        // arrives in the app's queue but never reaches the focused text field.
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility

    private func axInject(_ text: String) throws {
        guard AXIsProcessTrusted() else { throw InjectionError.accessibilityDenied }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard err == .success, let focused else { throw InjectionError.noFocusedElement }
        let element = focused as! AXUIElement

        // Try setting the selected text — works in Cocoa text views.
        let setErr = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if setErr != .success {
            throw InjectionError.attributeUnsupported
        }
    }
}
