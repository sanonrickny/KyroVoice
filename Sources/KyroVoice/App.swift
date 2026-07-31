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
        // End-to-end speech check. Separate flag because it downloads the model
        // and takes real time, unlike the instant offline text checks.
        if CommandLine.arguments.contains("--speech-check") {
            let sem = DispatchSemaphore(value: 0)
            Task.detached { await SpeechEngineSelfCheck.run() }
            sem.wait()  // SpeechEngineSelfCheck.run() never returns; it exits.
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
