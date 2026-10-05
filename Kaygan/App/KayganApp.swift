import AppKit
import SwiftUI

@main
struct KayganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            KayganMenuBarContent()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("Kaygan")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: appDelegate.settings,
                recorder: appDelegate.buttonRecorder,
                navigation: appDelegate.navigationEngine,
                generalSettings: appDelegate.generalSettings
            )
        }
    }
}

private struct KayganMenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }

        Divider()

        Button("Quit Kaygan") {
            NSApplication.shared.terminate(nil)
        }
    }
}
