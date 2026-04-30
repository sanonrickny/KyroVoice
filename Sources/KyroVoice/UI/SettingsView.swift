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
                .frame(minWidth: 480, minHeight: 360))

            let win = NSWindow(contentViewController: host)
            win.title = "KyroVoice Settings"
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

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var permissions: PermissionsService

    @State private var downloadingVariant: ModelVariant? = nil
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var downloadError: String? = nil

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "command") }
            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding()
        .onAppear { permissions.refresh() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker("Default mode", selection: $settings.mode) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Picker("Hotkey behavior", selection: $settings.hotkeyMode) {
                ForEach(HotkeyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Toggle("Enable Cloud AI cleanup (sends text to API)",
                   isOn: $settings.cloudCleanupEnabled)
        }
        .padding()
    }

    // MARK: - Hotkey

    private var hotkeyTab: some View {
        Form {
            HStack {
                Text("Dictation hotkey")
                Spacer()
                Text(settings.hotkey.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary))
            }
            Text("To change the hotkey, edit `Sources/KyroVoice/Models/HotkeyConfig.swift` and rebuild. A live recorder ships in v0.2.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Models

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ModelVariant.allCases) { variant in
                modelCard(variant)
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
                .padding(.top, 2)
            }

            Spacer()

            Text("Small models download automatically on first use. Large v3 Turbo must be downloaded manually before selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func modelCard(_ variant: ModelVariant) -> some View {
        let isActive          = settings.model == variant
        let isReady           = settings.isReadyToUse(variant)
        let isDownloadingThis = downloadingVariant == variant

        return HStack(spacing: 12) {
            Button {
                guard isReady else { return }
                settings.model = variant
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : (isReady ? Color.primary : Color.secondary))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!isReady)

            VStack(alignment: .leading, spacing: 2) {
                Text(variant.displayName)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(variant.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloadingThis {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
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
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
                    .foregroundStyle(.green)
            } else if isReady {
                Text("Downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Download  \(variant.approxDownloadMB) MB") {
                    startDownload(variant)
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(downloadingVariant != nil)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive
                      ? Color.accentColor.opacity(0.07)
                      : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
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

    private var permissionsTab: some View {
        Form {
            permissionRow(
                title: "Microphone",
                status: permissions.microphone,
                action: "Request",
                onAction: { Task { await permissions.requestMicrophone() } },
                onOpen: permissions.openSystemSettingsMicrophone
            )
            permissionRow(
                title: "Accessibility",
                status: permissions.accessibility,
                action: "Prompt",
                onAction: permissions.requestAccessibility,
                onOpen: permissions.openSystemSettingsAccessibility
            )
            permissionRow(
                title: "Input Monitoring",
                status: permissions.inputMonitoring,
                action: "Request",
                onAction: permissions.requestInputMonitoring,
                onOpen: permissions.openSystemSettingsInputMonitoring
            )

            HStack(spacing: 6) {
                Text("App folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.deletingLastPathComponent().path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        Bundle.main.bundleURL.deletingLastPathComponent().path,
                        forType: .string
                    )
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy path")
                Spacer()
                Button("Refresh") { permissions.refresh() }
            }
        }
        .padding()
    }

    private func permissionRow(
        title: String,
        status: PermissionStatus,
        action: String,
        onAction: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) -> some View {
        HStack {
            Circle()
                .fill(status.isGranted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(status.displayName)
                .foregroundStyle(.secondary)
            if status.isGranted {
                Button("Open Settings", action: onOpen)
            } else {
                Button(action, action: onAction)
            }
        }
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        Form {
            Picker("Text injection", selection: $settings.injectionStrategy) {
                ForEach(InjectionStrategyKind.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            Text("Pasteboard works in nearly every app (Slack, Chrome, VS Code). Accessibility is faster in Cocoa apps but unreliable in Electron.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
