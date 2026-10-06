@preconcurrency import ApplicationServices
import Foundation
import os

enum ScrollEngineFailure: Equatable, LocalizedError {
    case eventTapCreation
    case runLoopSourceCreation
    case eventTapRecovery

    var errorDescription: String? {
        switch self {
        case .eventTapCreation, .runLoopSourceCreation:
            "Kaygan couldn't start mouse features"
        case .eventTapRecovery:
            "Kaygan couldn't activate mouse features"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .eventTapCreation:
            "Kaygan couldn't create the mouse event monitor. Check that Kaygan has Accessibility access in System Settings, then retry."
        case .runLoopSourceCreation:
            "Kaygan couldn't activate the mouse monitor. Retry to start mouse features."
        case .eventTapRecovery:
            "Kaygan couldn't start or restore the mouse event monitor. Check Accessibility access in System Settings, then retry."
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

enum ScrollTapRecoveryAction: Equatable {
    case cancelLatchedScroll
    case stopForAccessibilityRevocation
    case retryPrimaryTap
    case stopAfterRepeatedTimeouts
}

enum ScrollTapKind: Equatable {
    case primary
    case latch
}

enum ScrollTapRecoveryPolicy {
    static func action(
        tapKind: ScrollTapKind,
        accessibilityTrusted: Bool,
        consecutiveTimeouts: Int,
        maximumTimeouts: Int
    ) -> ScrollTapRecoveryAction {
        guard accessibilityTrusted else { return .stopForAccessibilityRevocation }
        guard tapKind == .primary else { return .cancelLatchedScroll }
        guard consecutiveTimeouts <= maximumTimeouts else { return .stopAfterRepeatedTimeouts }
        return .retryPrimaryTap
    }
}

private enum TapDisableReason: String {
    case timeout
    case userInput = "user input"
}

@MainActor
final class ScrollEngine {
    private let logger = KayganLogger.scrolling
    var onTapInterruption: ((ScrollTapInterruption) -> Void)?
    var onOtherMouseDown: (@MainActor (Int) -> Bool)?
    var onNavigationButtonDown: (@MainActor (Int, String) -> Bool)?

    private let settings: AppSettings
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var latchTap: CFMachPort?
    private var latchSource: CFRunLoopSource?
    private var buttonLatched = false
    private var isSuspended = false
    private var didDrag = false
    private var pendingButtonDown: CGEvent?
    private var anchor: CGPoint?
    private var activeScrollButton: Int?
    private var activeScrollTargetBundleIdentifier: String?
    private var scrollGestureCancelled = false
    private var latchSuspendedForExcludedApp = false
    private var navigationButtonUps = Set<Int>()
    private var consecutiveTimeoutCount = 0
    private static let maxConsecutiveTimeouts = 3

    private var isScrolling: Bool {
        buttonHeld || buttonLatched
    }

    private var buttonHeld: Bool {
        activeScrollButton != nil
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isDisabled: Bool {
        settings.button == 0 && !settings.navigationEnabled
    }

    var isEventTapActive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private var speed: Int64 {
        settings.reverse ? -Int64(settings.speed) : Int64(settings.speed)
    }

    func start() -> ScrollEngineStartResult {
        guard tap == nil else { return .active }
        guard !isDisabled else { return .disabled }
        consecutiveTimeoutCount = 0

        // Mouse movement is only needed while toggle scrolling is latched.
        var events = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        events |= CGEventMask(1) << CGEventType.otherMouseDragged.rawValue
        events |= CGEventMask(1) << CGEventType.otherMouseUp.rawValue

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handle(proxy: proxy, type: type, event: event, tapKind: .primary)
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Could not create the event tap")
            return .failed(.eventTapCreation)
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            logger.error("Could not create the event tap run loop source")
            return .failed(.runLoopSourceCreation)
        }

        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        logger.info("Mouse features active (scroll button: \(self.settings.button), navigation: \(self.settings.navigationEnabled))")
        return .active
    }

    func stop() {
        resetState()
        consecutiveTimeoutCount = 0
        stopLatchTap()
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
        cancelActiveScrollGesture()
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { cancelActiveScrollGesture() }
    }

    private func resetState() {
        buttonLatched = false
        stopLatchTap()
        anchor = nil
        latchSuspendedForExcludedApp = false
        navigationButtonUps.removeAll()
        clearActiveScrollGesture()
    }

    func appExclusionsDidChange() {
        guard buttonHeld, activeScrollTargetIsExcludedOrUnknown() else { return }
        cancelActiveScrollGesture()
    }

    private func cancelActiveScrollGesture() {
        buttonLatched = false
        latchSuspendedForExcludedApp = false
        stopLatchTap()

        guard buttonHeld else {
            if let anchor { warpCursor(to: anchor, scrolling: false) }
            anchor = nil
            return
        }

        scrollGestureCancelled = true
        if let anchor {
            warpCursor(to: anchor, scrolling: false)
            self.anchor = nil
        }
    }

    private func activeScrollTargetIsExcludedOrUnknown() -> Bool {
        guard hasScrollingExclusions else { return false }
        guard let activeScrollTargetBundleIdentifier else { return true }
        return settings.scrollingIsDisabled(in: activeScrollTargetBundleIdentifier)
    }

    private var hasScrollingExclusions: Bool {
        settings.appExclusions.contains(where: { $0.scrollingDisabled })
    }

    private func clearActiveScrollGesture() {
        didDrag = false
        pendingButtonDown = nil
        activeScrollButton = nil
        activeScrollTargetBundleIdentifier = nil
        scrollGestureCancelled = false
    }

    private func discardStaleGestureState(for button: Int, at location: CGPoint) {
        navigationButtonUps.remove(button + 1)

        guard activeScrollButton == button else { return }
        clearActiveScrollGesture()
        if !buttonLatched {
            if anchor != nil { warpCursor(to: location, scrolling: false) }
            anchor = nil
        }
    }

    private func startLatchTap() -> Bool {
        guard latchTap == nil else { return true }
        let events = CGEventMask(1) << CGEventType.mouseMoved.rawValue
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handle(proxy: proxy, type: type, event: event, tapKind: .latch)
            }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            reportLatchTapFailure("Could not create the latched scrolling event tap")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            reportLatchTapFailure("Could not create the latched scrolling run loop source")
            return false
        }
        self.latchTap = tap
        self.latchSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    private func reportLatchTapFailure(_ message: String) {
        logger.error("\(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onTapInterruption?(.recoveryFailed)
        }
    }

    private func stopLatchTap() {
        if let latchSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), latchSource, .commonModes)
            CFRunLoopSourceInvalidate(latchSource)
            self.latchSource = nil
        }
        if let latchTap {
            CFMachPortInvalidate(latchTap)
            self.latchTap = nil
        }
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

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        tapKind: ScrollTapKind
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByUserInput:
            if tapKind == .primary { consecutiveTimeoutCount = 0 }
            handleDisabledTap(reason: .userInput, tapKind: tapKind)
            return nil

        case .tapDisabledByTimeout:
            if tapKind == .primary { consecutiveTimeoutCount += 1 }
            handleDisabledTap(reason: .timeout, tapKind: tapKind)
            return nil

        default:
            break
        }

        guard AXIsProcessTrustedWithOptions(nil) else {
            logger.warning("Received a mouse event after Accessibility permission was revoked; stopping event taps")
            stop()
            onTapInterruption?(.accessibilityRevoked)
            return Unmanaged.passUnretained(event)
        }

        if tapKind == .primary { consecutiveTimeoutCount = 0 }

        var downTargetBundleIdentifier: String?
        if type == .otherMouseDown {
            let eventButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            discardStaleGestureState(for: eventButton, at: event.location)

            // AppKit local monitors can miss clicks consumed by a control-tracking loop.
            let button = eventButton + 1
            if onOtherMouseDown?(button) == true {
                return Unmanaged.passUnretained(event)
            }

            downTargetBundleIdentifier = EventTargetResolver.bundleIdentifier(for: event)
            if settings.navigationEnabled,
               button != settings.button,
               (button == 4 || button == 5),
               let downTargetBundleIdentifier,
               onNavigationButtonDown?(button, downTargetBundleIdentifier) == true {
                navigationButtonUps.insert(button)
                return nil
            }
        }

        if type == .otherMouseUp {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if navigationButtonUps.remove(button) != nil { return nil }

            if buttonHeld,
               let activeScrollButton,
               button - 1 == activeScrollButton {
                return finishScrollGesture(proxy: proxy, event: event)
            }
        }

        switch type {
        case .otherMouseDown where isConfiguredScrollButton(event):
            if hasScrollingExclusions {
                guard let downTargetBundleIdentifier else {
                    return Unmanaged.passUnretained(event)
                }
                if settings.scrollingIsDisabled(in: downTargetBundleIdentifier) {
                    return Unmanaged.passUnretained(event)
                }
            }

            if !isScrolling {
                anchor = event.location
                warpCursor(to: event.location, scrolling: true)
            }
            didDrag = false
            scrollGestureCancelled = false
            activeScrollButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            activeScrollTargetBundleIdentifier = downTargetBundleIdentifier
            // Wait for release to distinguish a click from a drag-to-scroll gesture.
            pendingButtonDown = event.copy()
            return pendingButtonDown == nil ? Unmanaged.passUnretained(event) : nil
        case .otherMouseDragged where buttonHeld:
            return handleScrollMovement(event: event, latched: false)
        case .mouseMoved where buttonLatched:
            return handleScrollMovement(event: event, latched: true)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func isConfiguredScrollButton(_ event: CGEvent) -> Bool {
        // Settings use one-based button numbers; CGEvent uses zero-based numbers.
        !isSuspended && settings.button > 0
            && event.getIntegerValueField(.mouseEventButtonNumber) == settings.button - 1
    }

    private func finishScrollGesture(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        if !scrollGestureCancelled && settings.toggle {
            if didDrag {
                buttonLatched = false
                stopLatchTap()
            } else if buttonLatched {
                buttonLatched = false
                stopLatchTap()
            } else {
                buttonLatched = startLatchTap()
            }
        }

        let gestureMoved = didDrag
        if !gestureMoved, let pendingButtonDown {
            pendingButtonDown.tapPostEvent(proxy)
        }
        let shouldForwardUp = !gestureMoved || pendingButtonDown == nil
        clearActiveScrollGesture()

        if !isScrolling {
            anchor = nil
            warpCursor(to: event.location, scrolling: false)
        }
        return shouldForwardUp ? Unmanaged.passUnretained(event) : nil
    }

    private func handleScrollMovement(
        event: CGEvent,
        latched: Bool
    ) -> Unmanaged<CGEvent>? {
        let deltaX = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaX))
        let deltaY = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaY))
        if buttonHeld && (deltaX != 0 || deltaY != 0) { didDrag = true }

        if latched {
            if hasScrollingExclusions {
                guard let targetBundleIdentifier = EventTargetResolver.bundleIdentifier(for: event) else {
                    anchor = nil
                    latchSuspendedForExcludedApp = true
                    return Unmanaged.passUnretained(event)
                }
                if settings.scrollingIsDisabled(in: targetBundleIdentifier) {
                    anchor = nil
                    latchSuspendedForExcludedApp = true
                    return Unmanaged.passUnretained(event)
                }
            }
            if latchSuspendedForExcludedApp {
                anchor = event.location
                latchSuspendedForExcludedApp = false
                return Unmanaged.passUnretained(event)
            }
        } else {
            guard !scrollGestureCancelled else {
                return pendingButtonDown == nil ? Unmanaged.passUnretained(event) : nil
            }
            if hasScrollingExclusions {
                guard let activeScrollTargetBundleIdentifier else {
                    cancelActiveScrollGesture()
                    return pendingButtonDown == nil ? Unmanaged.passUnretained(event) : nil
                }
                if settings.scrollingIsDisabled(in: activeScrollTargetBundleIdentifier) {
                    cancelActiveScrollGesture()
                    return pendingButtonDown == nil ? Unmanaged.passUnretained(event) : nil
                }
            }
        }

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

        wheel.location = event.location
        wheel.flags = event.flags
        wheel.post(tap: .cgSessionEventTap)
        if let anchor { _ = CGWarpMouseCursorPosition(anchor) }
        return nil
    }

    private func handleDisabledTap(reason: TapDisableReason, tapKind: ScrollTapKind) {
        cancelActiveScrollGesture()

        switch ScrollTapRecoveryPolicy.action(
            tapKind: tapKind,
            accessibilityTrusted: AXIsProcessTrustedWithOptions(nil),
            consecutiveTimeouts: consecutiveTimeoutCount,
            maximumTimeouts: Self.maxConsecutiveTimeouts
        ) {
        case .cancelLatchedScroll:
            logger.warning("Latched scrolling event tap disabled by \(reason.rawValue, privacy: .public); toggle cancelled")
        case .stopForAccessibilityRevocation:
            logger.warning("Event tap disabled by \(reason.rawValue, privacy: .public); Accessibility permission is revoked")
            stop()
            onTapInterruption?(.accessibilityRevoked)
        case .stopAfterRepeatedTimeouts:
            logger.error("Event tap exceeded the limit of \(Self.maxConsecutiveTimeouts) consecutive timeouts; stopping")
            stop()
            onTapInterruption?(.recoveryFailed)
        case .retryPrimaryTap:
            guard let tap else {
                logger.error("Event tap disabled by \(reason.rawValue, privacy: .public); primary tap is unavailable")
                stop()
                onTapInterruption?(.recoveryFailed)
                return
            }

            CGEvent.tapEnable(tap: tap, enable: true)
            guard CGEvent.tapIsEnabled(tap: tap) else {
                logger.error("Could not re-enable the event tap after \(reason.rawValue, privacy: .public)")
                stop()
                onTapInterruption?(.recoveryFailed)
                return
            }

            if reason == .timeout {
                logger.warning("Primary event tap restored after timeout (attempt \(self.consecutiveTimeoutCount) of \(Self.maxConsecutiveTimeouts)); interrupted gesture cancelled")
            } else {
                logger.warning("Primary event tap restored after user input disabled it; interrupted gesture cancelled")
            }
        }
    }
}
