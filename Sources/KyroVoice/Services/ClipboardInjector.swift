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
    private let strategy: InjectionStrategyKind
    private let restoreDelay: TimeInterval

    public init(strategy: InjectionStrategyKind = .pasteboard, restoreDelay: TimeInterval = 0.20) {
        self.strategy = strategy
        self.restoreDelay = restoreDelay
    }

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func inject(_ text: String) async throws {
        guard !text.isEmpty else { return }
        switch strategy {
        case .pasteboard:    try await pasteboardInject(text)
        case .accessibility: try axInject(text)
        case .auto:
            do { try axInject(text) }
            catch { try await pasteboardInject(text) }
        }
    }

    // MARK: - Pasteboard + Cmd+V

    private func pasteboardInject(_ text: String) async throws {
        let pb = NSPasteboard.general

        // Snapshot full pasteboard (all types) for restore.
        let snapshot = snapshotPasteboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        try postCommandV()

        // Restore previous pasteboard contents shortly after the paste settles.
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
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InjectionError.inputMonitoringDenied
        }
        let vKey = CGKeyCode(kVK_ANSI_V)

        guard
            let cmdDown  = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
            let vDown    = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp      = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            let cmdUp    = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        else {
            throw InjectionError.inputMonitoringDenied
        }
        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand
        cmdUp.flags   = []

        let tap: CGEventTapLocation = .cghidEventTap
        cmdDown.post(tap: tap)
        vDown.post(tap: tap)
        vUp.post(tap: tap)
        cmdUp.post(tap: tap)
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
