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
        // Wide enough for error messages; transparent background makes
        // unused space invisible and ignoresMouseEvents keeps it click-through.
        let rect = NSRect(x: 0, y: 0, width: 300, height: 44)
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

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let inset: CGFloat = 24
            let origin = NSPoint(
                x: visible.origin.x + (visible.width - rect.width) / 2,
                y: visible.origin.y + inset
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
            HStack(spacing: 10) {
                micIcon
                WaveformBars(audioLevel: state.audioLevel, tint: .red, showsActivityPulse: true)
                    .frame(width: 51, height: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
                .tint(.purple)
                .frame(width: 20, height: 20)
                .padding(12)

        case .injected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18, weight: .semibold))
                .padding(12)

        case .error(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 22, height: 22)
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

        case .hidden:
            EmptyView()
        }
    }

    private var micIcon: some View {
        Group {
            if #available(macOS 14.0, *) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 22, height: 22)
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

struct WaveformBar: View {
    let amplitude: CGFloat
    let tint: Color
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 20

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.85))
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformBars: View {
    let audioLevel: Float
    let tint: Color
    var showsActivityPulse: Bool = false

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        Group {
            if showsActivityPulse {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    bars(pulseTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(pulseTime: nil)
            }
        }
        .frame(height: 20)
    }

    private func bars(pulseTime: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                WaveformBar(amplitude: amplitude(for: i, pulseTime: pulseTime), tint: tint)
                    .animation(
                        .spring(response: response(for: i), dampingFraction: 0.88)
                        .delay(delay(for: i)),
                        value: audioLevel
                    )
            }
        }
    }

    private func amplitude(for index: Int, pulseTime: TimeInterval?) -> CGFloat {
        let level = CGFloat(max(audioLevel, 0))
        let base = min(level * Self.multipliers[index], 1.0)
        guard let t = pulseTime else { return base }

        let wave = CGFloat(0.5 + 0.5 * sin((t * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((t * 3.1) + Double(index) * 0.5))
        let pulse = wave * 0.22 + shimmer * 0.06

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
