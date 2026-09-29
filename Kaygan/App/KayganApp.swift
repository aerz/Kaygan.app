import AppKit
import SwiftUI

@main
struct KayganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kaygan", systemImage: "arrow.up.and.down") {
            KayganMenuBarContent {
                appDelegate.prepareToOpenSettings()
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: appDelegate.settings,
                recorder: appDelegate.buttonRecorder,
                navigation: appDelegate.navigationEngine,
                setSettingsWindowOpen: appDelegate.setSettingsWindowOpen
            )
        }
    }
}

private struct KayganMenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    let prepareToOpenSettings: @MainActor () -> Void

    var body: some View {
        Button("Settings…") {
            prepareToOpenSettings()
            openSettings()
        }

        Divider()

        Button("Quit Kaygan") {
            NSApplication.shared.terminate(nil)
        }
    }
}
