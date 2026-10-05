import AppKit
import Foundation
import os

enum KayganLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aerz.Kaygan"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let scrolling = Logger(subsystem: subsystem, category: "scrolling")
}

enum KayganState: Equatable {
    case waitingForAccessibility
    case starting
    case active
    case disabled
    case failed(ScrollEngineFailure)
}

private enum FailureAction {
    case retry
    case quit
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let generalSettings: GeneralSettingsModel
    let buttonRecorder = MouseButtonRecorder()
    let navigationEngine: NavigationEngine
    private let engine: ScrollEngine
    private var accessibilityTimer: Timer?
    private var accessibilityGranted = false
    private var presentingFailure = false

    private(set) var state: KayganState = .waitingForAccessibility

    override init() {
        let settings = AppSettings()
        let generalSettings = GeneralSettingsModel()
        self.settings = settings
        self.generalSettings = generalSettings
        navigationEngine = NavigationEngine(settings: settings)
        engine = ScrollEngine(settings: settings)
        super.init()
        engine.onTapInterruption = { [weak self] interruption in
            self?.handleTapInterruption(interruption)
        }
        engine.onOtherMouseDown = { [weak self] button in
            self?.buttonRecorder.recordIfCapturing(button: button) ?? false
        }
        engine.onNavigationButtonDown = { [weak self] button in
            self?.navigationEngine.navigate(button: button) ?? false
        }
        buttonRecorder.onCaptureStateChange = { [weak self] isCapturing in
            self?.engine.setSuspended(isCapturing)
        }
        buttonRecorder.isEventTapActive = { [weak self] in
            self?.engine.isEventTapActive == true
        }
        observeSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installAccessibilityTimer()

        guard !engine.isDisabled else {
            state = .disabled
            KayganLogger.app.info("Scrolling and navigation are disabled in settings")
            return
        }

        let granted = generalSettings.requestAccessibility()
        accessibilityGranted = granted
        if granted {
            KayganLogger.app.info("Accessibility permission granted")
        } else {
            KayganLogger.app.info("Accessibility permission required")
        }

        if granted { startEngine() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        engine.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        navigationEngine.refreshPermission()
        generalSettings.refreshLoginItemStatus()
        refreshAccessibility()
    }

    private func installAccessibilityTimer() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityTimer = timer
    }

    private func refreshAccessibility() {
        let granted = generalSettings.refreshAccessibility()
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted

        if granted {
            KayganLogger.app.info("Accessibility permission granted")
            if !presentingFailure && !engine.isDisabled { startEngine() }
        } else {
            KayganLogger.app.warning("Accessibility permission revoked")
            engine.stop()
            state = .waitingForAccessibility
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.button
            _ = settings.speed
            _ = settings.reverse
            _ = settings.toggle
            _ = settings.navigationEnabled
            _ = settings.reverseNavigation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeSettings()
                self?.settingsDidChange()
            }
        }
    }

    private func settingsDidChange() {
        navigationEngine.settingsDidChange()
        engine.settingsDidChange()
        reconcileEngineState()
    }

    private func reconcileEngineState() {
        guard !presentingFailure else { return }

        guard !engine.isDisabled else {
            engine.stop()
            state = .disabled
            return
        }

        let wasDisabled = state == .disabled
        let granted: Bool
        if wasDisabled {
            granted = generalSettings.requestAccessibility()
        } else {
            granted = generalSettings.refreshAccessibility()
        }
        accessibilityGranted = granted

        guard granted else {
            engine.stop()
            state = .waitingForAccessibility
            return
        }

        if state != .active {
            startEngine()
        }
    }

    private func startEngine() {
        navigationEngine.settingsDidChange()
        state = .starting
        switch engine.start() {
        case .active:
            state = .active
        case .disabled:
            state = .disabled
        case .failed(let failure):
            presentFailure(failure)
        }
    }

    private func handleTapInterruption(_ interruption: ScrollTapInterruption) {
        guard state == .active else { return }

        switch interruption {
        case .accessibilityRevoked:
            engine.stop()
            accessibilityGranted = false
            generalSettings.refreshAccessibility()
            state = .waitingForAccessibility
            KayganLogger.app.warning("Accessibility permission revoked; stopping mouse features")
        case .recoveryFailed:
            engine.stop()
            state = .failed(.eventTapRecovery)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .failed(.eventTapRecovery) else { return }
                self.presentFailure(.eventTapRecovery)
            }
        }
    }

    private func presentFailure(_ failure: ScrollEngineFailure) {
        guard !presentingFailure else { return }
        accessibilityGranted = generalSettings.refreshAccessibility()
        guard accessibilityGranted else {
            engine.stop()
            state = .waitingForAccessibility
            return
        }

        engine.stop()
        presentingFailure = true
        state = .failed(failure)
        KayganLogger.app.error("Mouse features unavailable: \(String(describing: failure), privacy: .public)")

        let alert = NSAlert(error: failure)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit")
        NSApplication.shared.activate()
        let action: FailureAction = alert.runModal() == .alertFirstButtonReturn ? .retry : .quit
        Task { @MainActor [weak self] in
            self?.handleFailureAction(action)
        }
    }

    private func handleFailureAction(_ action: FailureAction) {
        presentingFailure = false
        switch action {
        case .quit:
            NSApp.terminate(nil)
        case .retry:
            accessibilityGranted = generalSettings.refreshAccessibility()
            guard accessibilityGranted else {
                state = .waitingForAccessibility
                return
            }
            startEngine()
        }
    }
}
