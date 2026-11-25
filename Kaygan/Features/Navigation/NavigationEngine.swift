@preconcurrency import ApplicationServices
import AppKit
import CoreFoundation
import Foundation
import Observation

enum NavigationDirection: Sendable, Equatable {
    case back
    case forward

    private var titles: Set<String> {
        switch self {
        case .back: ["back", "go back"]
        case .forward: ["forward", "go forward"]
        }
    }

    var logName: String {
        switch self {
        case .back: "back"
        case .forward: "forward"
        }
    }

    func matches(title: String) -> Bool {
        titles.contains(Self.normalized(title))
    }

    private static func normalized(_ title: String) -> String {
        var normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTitle.hasSuffix("...") {
            normalizedTitle.removeLast(3)
        }
        if normalizedTitle.hasSuffix("…") {
            normalizedTitle.removeLast()
        }
        return normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
@Observable
final class NavigationEngine {
    private let settings: AppSettings

    private var hasPostEventAccess = false
    private var navigationTask: Task<Void, Never>?
    private(set) var statusMessage: String?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func settingsDidChange() {
        refreshPermission()
    }

    func refreshPermission() {
        guard settings.navigationEnabled else {
            hasPostEventAccess = false
            statusMessage = nil
            return
        }

        hasPostEventAccess = CGPreflightPostEventAccess()
        if hasPostEventAccess { statusMessage = nil }
    }

    func navigate(button: Int, targetBundleIdentifier: String) -> Bool {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleIdentifier = frontmostApplication?.bundleIdentifier

        guard navigationIsAllowed(
            targetBundleIdentifier: targetBundleIdentifier,
            frontmostBundleIdentifier: frontmostBundleIdentifier
        ) else {
            return false
        }

        refreshPermission()
        guard hasPostEventAccess else {
            statusMessage = "Accessibility access is required. Open General and click Request Access."
            return false
        }

        let isBackButton = button == 4
        let goesBack = isBackButton != settings.reverseNavigation
        let navigationDirection: NavigationDirection = goesBack ? .back : .forward

        guard let frontmostApplication else {
            return postSwipeGesture(navigationDirection)
        }

        let processIdentifier = frontmostApplication.processIdentifier
        let previousTask = navigationTask
        navigationTask = Task { @MainActor [weak self] in
            _ = await previousTask?.value
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
                  navigationIsAllowed(
                      targetBundleIdentifier: targetBundleIdentifier,
                      frontmostBundleIdentifier: frontmostBundleIdentifier
                  ) else {
                return
            }

            let pressed = await Task.detached(priority: .userInitiated) {
                AppMenuNavigator.pressMenuItem(navigationDirection, in: processIdentifier)
            }.value

            if pressed {
                statusMessage = nil
                return
            }

            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
                  navigationIsAllowed(
                      targetBundleIdentifier: targetBundleIdentifier,
                      frontmostBundleIdentifier: frontmostBundleIdentifier
                  ) else {
                return
            }
            postSwipeGesture(navigationDirection)
        }
        return true
    }

    private func navigationIsAllowed(
        targetBundleIdentifier: String,
        frontmostBundleIdentifier: String?
    ) -> Bool {
        settings.navigationEnabled
            && !settings.navigationIsDisabled(in: targetBundleIdentifier)
            && frontmostBundleIdentifier.map(settings.navigationIsDisabled(in:)) != true
    }

    @discardableResult
    private func postSwipeGesture(_ navigationDirection: NavigationDirection) -> Bool {
        let direction = Self.swipeGestureDirection(for: navigationDirection)
        guard let begin = GestureEvent.make(phase: 1, direction: 0),
              let swipe = GestureEvent.make(phase: 4, direction: direction) else {
            statusMessage = "Kaygan couldn’t go back or forward in this app. Try again."
            return false
        }

        begin.post(tap: .cghidEventTap)
        swipe.post(tap: .cghidEventTap)
        statusMessage = nil
        return true
    }

    nonisolated static func swipeGestureDirection(for direction: NavigationDirection) -> UInt32 {
        direction == .back ? GestureSwipe.back : GestureSwipe.forward
    }
}

private enum GestureSwipe {
    static let back: UInt32 = 4
    static let forward: UInt32 = 8
}

private enum GestureEvent {
    private static let flattenedEventTailSize = 24
    private static let eventTypeGesture: UInt32 = 29
    private static let digitizerEventType: UInt32 = 11
    private static let vendorEventType: UInt32 = 1
    private static let digitizerEventSize: UInt32 = 92
    private static let vendorEventSize: UInt32 = 72
    private static let collectionOption: UInt32 = 2

    static func make(phase: UInt32, direction: UInt32) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        guard let type = CGEventType(rawValue: eventTypeGesture) else { return nil }
        event.type = type
        event.flags = CGEventFlags(rawValue: 0x100)
        let timestamp = event.timestamp
        guard let baseData = event.data else { return nil }

        var data = Data(referencing: baseData)
        guard data.count >= flattenedEventTailSize else { return nil }
        data.removeLast(flattenedEventTailSize)
        appendHIDCollection(timestamp: timestamp, to: &data)
        appendIntegerField(0x6E, value: 0x10, to: &data)
        appendIntegerField(0x6F, value: 0, to: &data)
        appendIntegerField(0x70, value: 0, to: &data)
        appendIntegerField(0x84, value: phase, to: &data)
        appendIntegerField(0x85, value: 0, to: &data)
        appendIntegerField(0x73, value: direction, to: &data)
        appendFloatField(0x8B, value: 0, to: &data)
        appendFloatField(0x8C, value: 0, to: &data)

        return CGEvent(withDataAllocator: nil, data: data as CFData)
    }

    private static func appendHIDCollection(timestamp: UInt64, to data: inout Data) {
        let collectionSize = UInt16(28 + Int(vendorEventSize) + Int(digitizerEventSize))
        data.appendBigEndian(collectionSize)
        data.append(contentsOf: [0x10, 0x6D])

        data.appendLittleEndian(timestamp)
        data.appendLittleEndian(UInt64(0))
        data.appendLittleEndian(collectionOption)
        data.appendLittleEndian(UInt32(0)) // attribute length
        data.appendLittleEndian(UInt32(2))

        data.appendLittleEndian(digitizerEventSize)
        data.appendLittleEndian(digitizerEventType)
        data.appendLittleEndian(collectionOption)
        data.appendLittleEndian(UInt32(0)) // event depth and reserved bytes
        data.appendLittleEndian(UInt32(0)) // x position
        data.appendLittleEndian(UInt32(0)) // y position
        data.appendLittleEndian(UInt32(0)) // z position
        data.appendLittleEndian(UInt32(0)) // transducer index
        data.appendLittleEndian(UInt32(0x23)) // hand transducer
        for _ in 0..<7 {
            data.appendLittleEndian(UInt32(0))
        }
        data.appendLittleEndian(UInt32(2)) // quality orientation
        for _ in 0..<6 {
            data.appendLittleEndian(UInt32(0))
        }

        data.appendLittleEndian(vendorEventSize)
        data.appendLittleEndian(vendorEventType)
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt32(0)) // event depth and reserved bytes
        data.appendLittleEndian(UInt16(0xFF00))
        data.appendLittleEndian(UInt16(0x1777))
        data.appendLittleEndian(UInt32(1))
        data.appendLittleEndian(UInt32(40))
        data.append(Data(repeating: 0, count: 44)) // vendor payload and trailing alignment
    }

    private static func appendIntegerField(_ field: UInt8, value: UInt32, to data: inout Data) {
        data.appendBigEndian(UInt16(1))
        data.append(contentsOf: [0x40, field])
        data.appendBigEndian(value)
    }

    private static func appendFloatField(_ field: UInt8, value: Float, to data: inout Data) {
        data.appendBigEndian(UInt16(1))
        data.append(contentsOf: [0xC0, field])
        data.appendBigEndian(value.bitPattern)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
