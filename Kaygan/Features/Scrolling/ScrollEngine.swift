@preconcurrency import ApplicationServices
import Foundation

enum ScrollEngineFailure: Equatable, LocalizedError {
    case eventTapCreation
    case runLoopSourceCreation
    case eventTapRecovery

    var errorDescription: String? {
        switch self {
        case .eventTapCreation, .runLoopSourceCreation:
            "Kaygan couldn't start mouse features"
        case .eventTapRecovery:
            "Kaygan stopped processing mouse features"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .eventTapCreation:
            "Kaygan couldn't create the mouse event monitor. Check that Kaygan has Accessibility access in System Settings, then retry."
        case .runLoopSourceCreation:
            "Kaygan couldn't activate the mouse monitor. Retry to start mouse features."
        case .eventTapRecovery:
            "macOS disabled the event monitor and Kaygan couldn't restore it. Retry to resume mouse features."
        }
    }
}

enum ScrollEngineStartResult {
    case active
    case disabled
    case failed(ScrollEngineFailure)
}

enum ScrollTapInterruption: Sendable {
    case accessibilityRevoked
    case recoveryFailed
}

@MainActor
final class ScrollEngine {
    var onTapInterruption: ((ScrollTapInterruption) -> Void)?
    var onOtherMouseDown: (@MainActor (Int) -> Bool)?
    var onNavigationButtonDown: (@MainActor (Int) -> Bool)?

    private let settings: AppSettings
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buttonHeld = false
    private var buttonLatched = false
    private var isSuspended = false
    private var didDrag = false
    private var pendingButtonDown: CGEvent?
    private var anchor: CGPoint?
    private var navigationButtonUps = Set<Int>()

    private var isScrolling: Bool {
        buttonHeld || buttonLatched
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isDisabled: Bool {
        settings.button == 0 && !settings.navigationEnabled
    }

    private var speed: Int64 {
        settings.reverse ? -Int64(settings.speed) : Int64(settings.speed)
    }

    func start() -> ScrollEngineStartResult {
        guard tap == nil else { return .active }
        guard !isDisabled else { return .disabled }

        var events = CGEventMask(1) << CGEventType.mouseMoved.rawValue
        events |= CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        events |= CGEventMask(1) << CGEventType.otherMouseDragged.rawValue
        events |= CGEventMask(1) << CGEventType.otherMouseUp.rawValue

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handle(proxy: proxy, type: type, event: event)
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Kaygan: could not create the event tap")
            return .failed(.eventTapCreation)
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            NSLog("Kaygan: could not create the event tap run loop source")
            return .failed(.runLoopSourceCreation)
        }

        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        NSLog("Kaygan: mouse features active (scroll button \(settings.button), navigation \(settings.navigationEnabled))")
        return .active
    }

    func stop() {
        resetState()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            self.source = nil
        }
        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    func settingsDidChange() {
        resetState()
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { resetState() }
    }

    private func resetState() {
        buttonHeld = false
        buttonLatched = false
        didDrag = false
        pendingButtonDown = nil
        anchor = nil
        navigationButtonUps.removeAll()
    }

    private func warpCursor(to point: CGPoint, scrolling: Bool) {
        // Use separate suppression intervals during scrolling and cursor release.
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            _ = CGWarpMouseCursorPosition(point)
            return
        }

        if scrolling {
            source.localEventsSuppressionInterval = 10
            _ = CGWarpMouseCursorPosition(point)
        } else {
            source.localEventsSuppressionInterval = 0
            _ = CGWarpMouseCursorPosition(point)
            source.localEventsSuppressionInterval = 0.25
        }
    }

    private func matchesButton(_ event: CGEvent) -> Bool {
        // Settings use one-based button numbers; CGEvent uses zero-based numbers.
        !isSuspended && event.getIntegerValueField(.mouseEventButtonNumber) == settings.button - 1
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .otherMouseDown {
            // AppKit local monitors can miss clicks consumed by a control-tracking loop.
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if onOtherMouseDown?(button) == true {
                return Unmanaged.passUnretained(event)
            }

            if settings.navigationEnabled,
               button != settings.button,
               (button == 4 || button == 5),
               onNavigationButtonDown?(button) == true {
                navigationButtonUps.insert(button)
                return nil
            }
        }

        if type == .otherMouseUp {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if navigationButtonUps.remove(button) != nil { return nil }
        }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            resetState()
            guard AXIsProcessTrusted() else {
                NSLog("Kaygan: event tap disabled; Accessibility revoked")
                onTapInterruption?(.accessibilityRevoked)
                break
            }
            guard let tap else {
                NSLog("Kaygan: event tap disabled")
                onTapInterruption?(.recoveryFailed)
                break
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                NSLog("Kaygan: event tap restored")
            } else {
                NSLog("Kaygan: event tap disabled")
                onTapInterruption?(.recoveryFailed)
            }
        case .otherMouseDown where matchesButton(event):
            if !isScrolling {
                anchor = event.location
                warpCursor(to: event.location, scrolling: true)
            }
            buttonHeld = true
            didDrag = false
            // Wait for release to distinguish a click from a drag-to-scroll gesture.
            pendingButtonDown = event.copy()
            return pendingButtonDown == nil ? Unmanaged.passUnretained(event) : nil
        case .otherMouseUp where matchesButton(event) && buttonHeld:
            buttonHeld = false
            if settings.toggle {
                if didDrag { buttonLatched = false }
                else { buttonLatched.toggle() }
            }
            let didScroll = didDrag
            if !didScroll, let pendingButtonDown {
                pendingButtonDown.tapPostEvent(proxy)
            }
            let shouldForwardUp = !didScroll || pendingButtonDown == nil
            pendingButtonDown = nil
            didDrag = false
            if !isScrolling {
                anchor = nil
                warpCursor(to: event.location, scrolling: false)
            }
            return shouldForwardUp ? Unmanaged.passUnretained(event) : nil
        case .mouseMoved where isScrolling, .otherMouseDragged where isScrolling:
            let deltaX = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaY))
            if buttonHeld && (deltaX != 0 || deltaY != 0) { didDrag = true }

            let vertical = Int32(clamping: -speed * Int64(deltaY))
            let horizontal = Int32(clamping: -speed * Int64(deltaX))
            guard let wheel = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
            ) else { return Unmanaged.passUnretained(event) }

            wheel.tapPostEvent(proxy)
            if let anchor { _ = CGWarpMouseCursorPosition(anchor) }
            return nil
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
