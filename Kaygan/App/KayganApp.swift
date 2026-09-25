import SwiftUI

@main
struct KayganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings, recorder: appDelegate.buttonRecorder)
        }
    }
}
