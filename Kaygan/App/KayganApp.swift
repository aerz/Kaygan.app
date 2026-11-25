import AppKit
import SwiftUI

@main
struct KayganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            KayganMenuBarContent(appDelegate: appDelegate)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("Kaygan")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct KayganMenuBarContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Settings…") {
            appDelegate.showSettings()
        }

        Divider()

        Button("Quit Kaygan") {
            NSApplication.shared.terminate(nil)
        }
    }
}
