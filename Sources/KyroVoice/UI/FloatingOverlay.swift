import Foundation
import AppKit
import SwiftUI
import Combine

/// Borderless, non-activating, top-right floating panel that shows
/// recording / processing / injected state with a small animated waveform.
@MainActor
public final class FloatingOverlay {
    private var panel: NSPanel?
    private let state: OverlayState
    private var hideWorkItem: DispatchWorkItem?
    private var phaseSink: AnyCancellable?

    public init(state: OverlayState) {
        self.state = state
        // The panel follows the phase instead of waiting to be told. Every
        // "the pebble did not show up" bug was a phase change that no call site
        // paired with a show(): `stopAndTranscribe` sets `.processing` and
        // nothing else, so a session that began with the panel down stayed
        // down for its whole life. One subscription, no call site to forget.
        phaseSink = state.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if phase == .hidden { self.hide() } else { self.show() }
                }
            }
    }

    /// Read by `--overlay-check`.
    var isPanelVisible: Bool { panel?.isVisible ?? false }
    var panelFrame: NSRect? { panel?.frame }
    var panelLevel: Int { panel.map { $0.level.rawValue } ?? .min }

    public func show() {
        ensurePanel()
        repositionPanel()
        panel?.orderFrontRegardless()
        cancelHide()
    }

    /// Builds and draws the panel once, invisibly, at launch. The first show
    /// otherwise spends ~85 ms creating the panel and SwiftUI host.
    public func prewarm() {
        guard panel == nil else { return }
        ensurePanel()
        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    public func hide() {
        cancelHide()
        panel?.orderOut(nil)
    }

    public func scheduleHide(after seconds: TimeInterval) {
        cancelHide()
        // Setting the phase is enough: the subscription takes the panel down.
        let work = DispatchWorkItem { [weak self] in
            self?.state.phase = .hidden
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func repositionPanel() {
        // NSScreen.main is the screen with the *key window*. An .accessory app
        // whose only window is a nonactivating panel never has one, so this
        // always resolved to the menu-bar display and the HUD appeared on the
        // wrong monitor. The screen under the cursor is where the user is.
        let cursorScreen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }
        guard let panel, let screen = cursorScreen ?? NSScreen.main else { return }
        let rect = panel.frame
        let visible = screen.visibleFrame
        let inset: CGFloat = 24
        let origin = NSPoint(
            x: visible.origin.x + (visible.width - rect.width) / 2,
            y: visible.origin.y + inset
        )
        panel.setFrameOrigin(origin)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        // Wide enough for error messages; transparent background makes
        // unused space invisible and ignoresMouseEvents keeps it click-through.
        let rect = NSRect(x: 0, y: 0, width: 260, height: 36)
        let p = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        // .floating is level 3, below the Dock (20) and the menu bar (24), so
        // the pebble sits under the Dock the moment a full-screen space hides
        // it from `visibleFrame` and the user nudges the pointer downwards.
        p.level = .statusBar
        // .fullScreenAuxiliary allows the panel to appear over fullscreen app spaces.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true

        let host = NSHostingView(rootView: OverlayView(state: state))
        host.frame = rect
        host.autoresizingMask = [.width, .height]
        p.contentView = host

        panel = p
    }
}

// MARK: - SwiftUI content

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.phase != .hidden {
                pillContent
                    .background(pillBackground)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: state.phase)
    }

    @ViewBuilder
    private var pillContent: some View {
        switch state.phase {
        case .listening:
            // ponytail: bars only. The mic glyph said nothing the bars don't.
            WaveformBars(audioLevel: state.audioLevel)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.65)
                .tint(.purple)
                .frame(width: 16, height: 16)
                .padding(10)

        case .injected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14, weight: .semibold))
                .padding(10)

        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    // Wrap inside the panel. `horizontal: true` forced the text
                    // to its full single-line width, so a 97-character error
                    // like the mic-denied message rendered ~500 pt wide in a
                    // 260 pt panel and the user saw a centred fragment.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)

        case .hidden:
            EmptyView()
        }
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// The listening pebble: a bank of capsules whose heights track the live input
/// level, with a travelling shimmer so it still breathes during silence.
///
/// `Color.primary` rather than a fixed white: the panel inherits the system
/// appearance, and white bars vanish on the light-mode material.
struct WaveformBars: View {
    let audioLevel: Float

    private static let barCount = 11
    private static let centerIndex = CGFloat(barCount - 1) / 2
    private static let minHeight: CGFloat = 2.5
    private static let maxHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: 2.5, height: height(for: i, at: t))
                        .animation(
                            .spring(response: response(for: i), dampingFraction: 0.88)
                            .delay(delay(for: i)),
                            value: audioLevel
                        )
                }
            }
        }
        .frame(height: Self.maxHeight)
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let a = amplitude(for: index, at: time)
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * a
    }

    /// Bell-shaped envelope, tallest in the middle, scaled by the live level.
    private static func envelope(_ index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(barCount - 1)
        return 0.35 + 0.65 * sin(t * .pi)
    }

    private func amplitude(for index: Int, at time: TimeInterval) -> CGFloat {
        let level = CGFloat(max(audioLevel, 0))
        let base = min(level * Self.envelope(index), 1.0)

        let wave = CGFloat(0.5 + 0.5 * sin((time * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((time * 3.1) + Double(index) * 0.5))
        let pulse = wave * 0.22 + shimmer * 0.06

        // Loud → the envelope dominates; silent → only the idle shimmer is left.
        return min(base * (0.74 + pulse) + (1.0 - base) * (0.04 + pulse * 0.28), 1.0)
    }

    private func response(for index: Int) -> Double {
        let dist = abs(CGFloat(index) - Self.centerIndex) / Self.centerIndex
        return 0.18 + Double(dist) * 0.06
    }

    private func delay(for index: Int) -> Double {
        Double(abs(CGFloat(index) - Self.centerIndex)) * 0.01
    }
}
