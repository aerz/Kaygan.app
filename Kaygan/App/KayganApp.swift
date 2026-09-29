import AppKit
import SwiftUI

@main
struct KayganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            KayganMenuBarContent {
                appDelegate.prepareToOpenSettings()
            }
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
