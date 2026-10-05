@preconcurrency import ApplicationServices
import Foundation
import Observation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        self == .enabled
    }

    var registrationIsActiveOrPending: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol AccessibilityTrustProviding {
    func isTrusted() -> Bool
    func requestAccess() -> Bool
}

@MainActor
protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func openLoginItems()
}

@MainActor
@Observable
final class GeneralSettingsModel {
    private(set) var isAccessibilityTrusted: Bool
    private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    private(set) var launchAtLoginErrorMessage: String?

    private let accessibility: any AccessibilityTrustProviding
    private let loginItem: any LaunchAtLoginManaging

    var launchAtLoginIsEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    var launchAtLoginActionTitle: String? {
        switch launchAtLoginStatus {
        case .notRegistered, .notFound: "Turn on"
        case .enabled: nil
        case .requiresApproval: "Open Login Items…"
        }
    }

    init() {
        let accessibility = SystemAccessibilityTrustProvider()
        let loginItem = SystemLaunchAtLoginManager()
        self.accessibility = accessibility
        self.loginItem = loginItem
        isAccessibilityTrusted = accessibility.isTrusted()
        launchAtLoginStatus = loginItem.status
    }

    init(
        accessibility: any AccessibilityTrustProviding,
        loginItem: any LaunchAtLoginManaging
    ) {
        self.accessibility = accessibility
        self.loginItem = loginItem
        isAccessibilityTrusted = accessibility.isTrusted()
        launchAtLoginStatus = loginItem.status
    }

    @discardableResult
    func refreshAccessibility() -> Bool {
        let isTrusted = accessibility.isTrusted()
        isAccessibilityTrusted = isTrusted
        return isTrusted
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        let isTrusted = accessibility.isTrusted() || accessibility.requestAccess()
        isAccessibilityTrusted = isTrusted
        return isTrusted
    }

    func refreshLoginItemStatus() {
        launchAtLoginStatus = loginItem.status
        launchAtLoginErrorMessage = nil
    }

    private func registerLaunchAtLogin() {
        launchAtLoginErrorMessage = nil

        do {
            try loginItem.register()
        } catch {
            launchAtLoginStatus = loginItem.status

            if !launchAtLoginStatus.registrationIsActiveOrPending {
                launchAtLoginErrorMessage = error.localizedDescription
            }
            return
        }

        launchAtLoginStatus = loginItem.status
    }

    func performLaunchAtLoginAction() {
        switch launchAtLoginStatus {
        case .notRegistered, .notFound:
            registerLaunchAtLogin()
        case .enabled:
            return
        case .requiresApproval:
            openLoginItems()
        }
    }

    func openLoginItems() {
        loginItem.openLoginItems()
    }
}

@MainActor
private struct SystemAccessibilityTrustProvider: AccessibilityTrustProviding {
    func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    func requestAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}

@MainActor
private struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
