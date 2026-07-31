import Foundation
import SwiftUI
import AppKit

// MARK: - HistoryWindow

@MainActor
public final class HistoryWindow {
    public static let shared = HistoryWindow()
    private var window: NSWindow?
    private init() {}

    public func show() {
        // Entries expire on a 24 h TTL that was only applied on add/load, so a
        // quiet day left expired rows on screen.
        HistoryStore.shared.pruneNow()
        if window == nil {
            let host = NSHostingController(rootView: HistoryView()
                .environmentObject(HistoryStore.shared)
                .frame(minWidth: 420, minHeight: 420))
            let win = NSWindow(contentViewController: host)
            win.title = "Dictation History"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @EnvironmentObject var store: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if store.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation History")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    store.entries.isEmpty
                        ? "No entries yet"
                        : "\(store.entries.count) item\(store.entries.count == 1 ? "" : "s") — kept for 24 hours"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.entries.isEmpty {
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Text("Clear All").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No dictation history")
                .font(.system(size: 15, weight: .medium))
            Text("Your transcribed text will appear here\nand be kept for 24 hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.entries) { entry in
                    HistoryEntryRow(entry: entry)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - HistoryEntryRow

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                modeBadge
                if let appName = entry.targetAppName {
                    Text(appName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(entry.text)
                .font(.system(size: 13))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                    }
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy",
                        systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var modeBadge: some View {
        let (label, color) = modeBadgeInfo
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var modeBadgeInfo: (String, Color) {
        switch entry.mode {
        case .normal: return ("Normal", .blue)
        case .email:  return ("Email", .purple)
        case .code:   return ("Code", .orange)
        }
    }

    // DateFormatter is expensive to build; this ran once per row per body
    // evaluation in a lazily-scrolled list of hundreds of entries.
    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let olderFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f
    }()

    private var formattedTimestamp: String {
        let isToday = Calendar.current.isDateInToday(entry.timestamp)
        let fmt = isToday ? Self.todayFormatter : Self.olderFormatter
        return fmt.string(from: entry.timestamp)
    }
}
