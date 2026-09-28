@preconcurrency import ApplicationServices
import AppKit
import Foundation

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
    let buttonRecorder = MouseButtonRecorder()
    let navigationEngine: NavigationEngine
    private let engine: ScrollEngine
    private var accessibilityTimer: Timer?
    private var accessibilityGranted = false
    private var presentingFailure = false

    private(set) var state: KayganState = .waitingForAccessibility

    override init() {
        let settings = AppSettings()
        self.settings = settings
        navigationEngine = NavigationEngine(settings: settings)
        engine = ScrollEngine(settings: settings)
        super.init()
        engine.onTapInterruption = { [weak self] interruption in
            Task { @MainActor [weak self] in
                self?.handleTapInterruption(interruption)
            }
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
            NSLog("Kaygan: scrolling and navigation are disabled")
            return
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        NSLog("Kaygan: Accessibility \(accessibilityGranted ? "granted" : "required")")

        if accessibilityGranted { startEngine() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        engine.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        navigationEngine.refreshPermission()
    }

    private func installAccessibilityTimer() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityTimer = timer
    }

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        guard granted != accessibilityGranted else { return }

        accessibilityGranted = granted
        NSLog("Kaygan: Accessibility \(granted ? "granted" : "revoked")")
        if granted {
            if !presentingFailure && !engine.isDisabled { startEngine() }
        } else {
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
        if wasDisabled, !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            granted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        } else {
            granted = AXIsProcessTrusted()
        }

        guard granted else {
            accessibilityGranted = false
            engine.stop()
            state = .waitingForAccessibility
            return
        }

        accessibilityGranted = true
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
            state = .waitingForAccessibility
            NSLog("Kaygan: Accessibility revoked")
        case .recoveryFailed:
            presentFailure(.eventTapRecovery)
        }
    }

    private func presentFailure(_ failure: ScrollEngineFailure) {
        guard !presentingFailure else { return }
        guard AXIsProcessTrusted() else {
            accessibilityGranted = false
            engine.stop()
            state = .waitingForAccessibility
            return
        }

        engine.stop()
        presentingFailure = true
        state = .failed(failure)
        NSLog("Kaygan: mouse features unavailable (\(String(describing: failure)))")

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
            guard AXIsProcessTrusted() else {
                accessibilityGranted = false
                state = .waitingForAccessibility
                return
            }
            accessibilityGranted = true
            startEngine()
        }
    }
}
