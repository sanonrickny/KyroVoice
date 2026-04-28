import Foundation
import SwiftUI
import AppKit

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
        Form {
            Picker("Whisper model", selection: $settings.model) {
                ForEach(ModelVariant.allCases) { v in
                    Text(v.displayName).tag(v)
                }
            }
            Text("Model files are downloaded once on first use into ~/Library/Application Support/KyroVoice/Models. The download is ≈\(settings.model.approxDownloadMB) MB.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
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
                action: "Open Settings",
                onAction: permissions.openSystemSettingsInputMonitoring,
                onOpen: permissions.openSystemSettingsInputMonitoring
            )

            HStack {
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
