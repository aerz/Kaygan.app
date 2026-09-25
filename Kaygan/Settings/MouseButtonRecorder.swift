import AppKit
import Observation

@MainActor
@Observable
final class MouseButtonRecorder {
    private(set) var isCapturing = false
    @ObservationIgnored var onCapture: ((Int) -> Void)?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    private nonisolated static let captureTimeout: Duration = .seconds(15)
    private nonisolated static let escapeKeyCode: UInt16 = 53

    func start() {
        guard !isCapturing else { return }
        isCapturing = true

        // A global monitor never receives events sent to Kaygan's own windows, so capture
        // listens on both paths; only the global handler is asynchronous. Buttons arrive
        // zero-based and Settings store them one-based.
        track(NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            let button = event.buttonNumber + 1
            Task { @MainActor [weak self] in
                self?.record(button: button)
            }
        })

        track(NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.record(button: event.buttonNumber + 1) }
            return event
        })

        track(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            MainActor.assumeIsolated { self?.cancel() }
            return nil
        })

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
