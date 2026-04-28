import Foundation
import AppKit
import SwiftUI

/// Borderless, non-activating, top-right floating panel that shows
/// recording / processing / injected state with a small animated waveform.
@MainActor
public final class FloatingOverlay {
    private var panel: NSPanel?
    private let state: OverlayState
    private var hideWorkItem: DispatchWorkItem?

    public init(state: OverlayState) {
        self.state = state
    }

    public func show() {
        ensurePanel()
        panel?.orderFrontRegardless()
        cancelHide()
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func scheduleHide(after seconds: TimeInterval) {
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            self?.state.phase = .hidden
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let rect = NSRect(x: 0, y: 0, width: 156, height: 48)
        let p = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true

        let host = NSHostingView(rootView: OverlayView(state: state))
        host.frame = rect
        p.contentView = host

        // Position top-right of the main screen.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let inset: CGFloat = 16
            let origin = NSPoint(
                x: visible.maxX - rect.width - inset,
                y: visible.maxY - rect.height - inset
            )
            p.setFrameOrigin(origin)
        }

        panel = p
    }
}

// MARK: - SwiftUI content

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 10) {
            iconView
            WaveformBars(levels: state.levels, tint: tint)
                .frame(width: 70, height: 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 156, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .opacity(state.phase == .hidden ? 0 : 1)
        .animation(.easeInOut(duration: 0.18), value: state.phase)
    }

    private var iconView: some View {
        Group {
            switch state.phase {
            case .listening:
                if #available(macOS 14.0, *) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                }
            case .processing:
                Image(systemName: "waveform")
                    .foregroundStyle(.purple)
            case .injected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .hidden:
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 22, height: 22)
    }

    private var tint: Color {
        switch state.phase {
        case .listening:  return .red
        case .processing: return .purple
        case .injected:   return .green
        case .error:      return .orange
        case .hidden:     return .secondary
        }
    }
}

struct WaveformBars: View {
    let levels: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: 4, height: max(3, CGFloat(levels[i]) * geo.size.height))
                        .animation(.easeOut(duration: 0.08), value: levels[i])
                }
            }
            .frame(height: geo.size.height, alignment: .center)
        }
    }
}
