import Foundation
import SwiftUI
import AppKit
import WhisperKit

@MainActor
public final class SettingsWindow {
    public static let shared = SettingsWindow()

    private var window: NSWindow?

    private init() {}

    public func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView()
                .environmentObject(SettingsStore.shared)
                .environmentObject(PermissionsHolder.shared.service)
                .frame(minWidth: 560, minHeight: 420))

            let win = NSWindow(contentViewController: host)
            win.title = "KyroVoice"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class PermissionsHolder {
    static let shared = PermissionsHolder()
    let service = PermissionsService()
    private init() {}
}

// MARK: - Section

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, hotkey, models, permissions, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .hotkey:      return "Hotkey"
        case .models:      return "Models"
        case .permissions: return "Permissions"
        case .advanced:    return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .hotkey:      return "command.circle.fill"
        case .models:      return "cube.fill"
        case .permissions: return "lock.shield.fill"
        case .advanced:    return "slider.horizontal.3"
        }
    }

    var accent: Color {
        switch self {
        case .general:     return .blue
        case .hotkey:      return .orange
        case .models:      return .purple
        case .permissions: return .green
        case .advanced:    return .gray
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var permissions: PermissionsService

    @State private var selected: SettingsSection = .general
    @State private var downloadingVariant: ModelVariant? = nil
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var downloadError: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { permissions.refresh() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                navButton(section)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .frame(width: 175)
        .background(.ultraThinMaterial)
    }

    private func navButton(_ section: SettingsSection) -> some View {
        let isSelected = selected == section
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selected = section }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(section.accent.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(section.accent)
                }
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content routing

    @ViewBuilder
    private var contentArea: some View {
        switch selected {
        case .general:     generalContent
        case .hotkey:      hotkeyContent
        case .models:      modelsContent
        case .permissions: permissionsContent
        case .advanced:    advancedContent
        }
    }

    // MARK: - General

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(.general)

                card {
                    pickerRow(label: "Default mode",
                              hint: "Applied when no app-specific rule matches") {
                        Picker("", selection: $settings.mode) {
                            ForEach(DictationMode.allCases) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 148)
                    }
                    rowDivider()
                    pickerRow(label: "Hotkey behavior",
                              hint: "How the hotkey activates dictation") {
                        Picker("", selection: $settings.hotkeyMode) {
                            ForEach(HotkeyMode.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 148)
                    }
                }

                card {
                    toggleRow(label: "Cloud AI cleanup",
                              hint: "Polishes transcriptions via AI — requires internet",
                              isOn: $settings.cloudCleanupEnabled)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Hotkey

    private var hotkeyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(.hotkey)

                card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictation hotkey")
                                .font(.system(size: 13, weight: .medium))
                            Text("Current shortcut")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(settings.hotkey.displayString)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }
                }

                infoNote("To change the hotkey, edit HotkeyConfig.swift and rebuild. A live recorder ships in v0.2.")
            }
            .padding(24)
        }
    }

    // MARK: - Models

    private var modelsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(.models)

                VStack(spacing: 8) {
                    ForEach(ModelVariant.allCases) { variant in
                        modelCard(variant)
                    }
                }

                if let error = downloadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                infoNote("Small models download on first use. Large v3 Turbo must be downloaded before selection.")
            }
            .padding(24)
        }
    }

    private func modelCard(_ variant: ModelVariant) -> some View {
        let isActive          = settings.model == variant
        let isReady           = settings.isReadyToUse(variant)
        let isDownloadingThis = downloadingVariant == variant

        return Button {
            guard isReady else { return }
            settings.model = variant
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.displayName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(variant.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloadingThis {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Downloading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            downloadTask?.cancel()
                            downloadTask = nil
                            downloadingVariant = nil
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                } else if isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                        Text("Active")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else if isReady {
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Download  \(variant.approxDownloadMB) MB") {
                        startDownload(variant)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(downloadingVariant != nil)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
    }

    private func startDownload(_ variant: ModelVariant) {
        downloadingVariant = variant
        downloadError = nil
        downloadTask = Task {
            do {
                let config = WhisperKitConfig(
                    model: variant.rawValue,
                    verbose: false,
                    logLevel: .error,
                    prewarm: false,
                    load: false,
                    download: true
                )
                _ = try await WhisperKit(config)
                guard !Task.isCancelled else { return }
                settings.markDownloaded(variant)
                settings.model = variant
                downloadingVariant = nil
                downloadTask = nil
            } catch is CancellationError {
                downloadingVariant = nil
                downloadTask = nil
            } catch {
                downloadError = error.localizedDescription
                downloadingVariant = nil
                downloadTask = nil
            }
        }
    }

    // MARK: - Permissions

    private var permissionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(.permissions)

                card {
                    permRow(title: "Microphone",
                            description: "Record audio for transcription",
                            icon: "mic.fill", iconColor: .red,
                            status: permissions.microphone,
                            actionLabel: "Request",
                            onAction: { Task { await permissions.requestMicrophone() } },
                            onOpen: permissions.openSystemSettingsMicrophone)
                    rowDivider()
                    permRow(title: "Accessibility",
                            description: "Insert text into other apps",
                            icon: "hand.point.up.fill", iconColor: .blue,
                            status: permissions.accessibility,
                            actionLabel: "Prompt",
                            onAction: permissions.requestAccessibility,
                            onOpen: permissions.openSystemSettingsAccessibility)
                    rowDivider()
                    permRow(title: "Input Monitoring",
                            description: "Detect the global hotkey",
                            icon: "keyboard.fill", iconColor: .orange,
                            status: permissions.inputMonitoring,
                            actionLabel: "Request",
                            onAction: permissions.requestInputMonitoring,
                            onOpen: permissions.openSystemSettingsInputMonitoring)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App location")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(Bundle.main.bundleURL.deletingLastPathComponent().path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            Bundle.main.bundleURL.deletingLastPathComponent().path,
                            forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                    Button("Refresh") { permissions.refresh() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
    }

    private func permRow(
        title: String,
        description: String,
        icon: String,
        iconColor: Color,
        status: PermissionStatus,
        actionLabel: String,
        onAction: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                statusPill(status)
                if status.isGranted {
                    Button("Settings", action: onOpen)
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button(actionLabel, action: onAction)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    private func statusPill(_ status: PermissionStatus) -> some View {
        let green = status.isGranted
        return HStack(spacing: 4) {
            Circle()
                .fill(green ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(green ? Color.green : Color.orange)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(green ? Color.green.opacity(0.1) : Color.orange.opacity(0.1)))
    }

    // MARK: - Advanced

    private var advancedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(.advanced)

                card {
                    pickerRow(label: "Text injection", hint: nil) {
                        Picker("", selection: $settings.injectionStrategy) {
                            ForEach(InjectionStrategyKind.allCases) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                infoNote("Pasteboard works in nearly every app. Accessibility is faster in Cocoa apps but unreliable in Electron-based apps.")
            }
            .padding(24)
        }
    }

    // MARK: - Design primitives

    private func sectionHeader(_ section: SettingsSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(section.accent)
            Text(section.title)
                .font(.system(size: 18, weight: .bold))
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
            )
    }

    private func rowDivider() -> some View {
        Divider().padding(.vertical, 8)
    }

    private func pickerRow<Control: View>(
        label: String,
        hint: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
    }

    private func toggleRow(label: String, hint: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}
