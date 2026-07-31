import SwiftUI
import AppKit

@main
struct KyroVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Runs the text-pipeline checks and exits before any UI comes up.
        if CommandLine.arguments.contains("--self-check") {
            TextProcessorSelfCheck.run()
        }
    }

    var body: some Scene {
        // No primary window. The Settings scene lets ⌘, open the panel and
        // satisfies SwiftUI's requirement of at least one Scene.
        Settings {
            SettingsView()
                .environmentObject(SettingsStore.shared)
                .environmentObject(PermissionsHolder.shared.service)
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}
