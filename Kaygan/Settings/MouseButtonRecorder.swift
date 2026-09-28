import AppKit
import Observation

@MainActor
@Observable
final class MouseButtonRecorder {
    private(set) var isCapturing = false
    private(set) var isCaptureUnavailable = false
    @ObservationIgnored var onCapture: ((Int) -> Void)?
    @ObservationIgnored var onCaptureStateChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var isEventTapActive: (@MainActor () -> Bool)?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    private nonisolated static let captureTimeout: Duration = .seconds(15)
    private nonisolated static let escapeKeyCode: UInt16 = 53

    func start() {
        guard !isCapturing else { return }
        isCaptureUnavailable = false
        onCaptureStateChange?(true)
        isCapturing = true

        // A global monitor never receives events sent to Kaygan's own windows, so capture
        // listens on both paths; only the global handler is asynchronous. Buttons arrive
        // zero-based and Settings store them one-based.
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            let button = event.buttonNumber + 1
            Task { @MainActor [weak self] in
                self?.record(button: button)
            }
        }
        track(globalMonitor)

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.record(button: event.buttonNumber + 1) }
            return event
        }
        track(localMonitor)

        track(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            MainActor.assumeIsolated { self?.cancel() }
            return nil
        })

        guard isEventTapActive?() == true || (globalMonitor != nil && localMonitor != nil) else {
            cancel()
            isCaptureUnavailable = true
            return
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.captureTimeout)
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }

    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        isCapturing = false
        isCaptureUnavailable = false
        onCaptureStateChange?(false)
    }

    func recordIfCapturing(button: Int) -> Bool {
        guard isCapturing else { return false }
        record(button: button)
        return true
    }

    private func track(_ monitor: Any?) {
        guard let monitor else { return }
        monitors.append(monitor)
    }

    private func record(button: Int) {
        guard isCapturing, AppSettings.isValidButton(button) else { return }
        cancel()
        onCapture?(button)
    }
}
