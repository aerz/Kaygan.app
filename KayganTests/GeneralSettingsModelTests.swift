import Foundation
import Testing
@testable import Kaygan

@MainActor
struct GeneralSettingsModelTests {
    @Test
    func accessibilityRequestWaitsForTrustToBeGranted() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: false)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(!model.isAccessibilityTrusted)
        #expect(!model.requestAccessibility())
        #expect(!model.isAccessibilityTrusted)
        #expect(accessibility.requestCount == 1)

        accessibility.isTrustedValue = true
        #expect(model.refreshAccessibility())
        #expect(model.isAccessibilityTrusted)
    }

    @Test
    func accessibilityRequestDoesNotPromptWhenAlreadyTrusted() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(model.requestAccessibility())
        #expect(accessibility.requestCount == 0)
    }

    @Test
    func approvalRequiredDoesNotShowEnabledAndOpensLoginItems() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .requiresApproval)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(!model.launchAtLoginIsEnabled)
        #expect(model.launchAtLoginActionTitle == "Open Login Items…")

        model.performLaunchAtLoginAction()
        #expect(loginItem.openLoginItemsCount == 1)
    }

    @Test
    func loginItemConfirmationIsOnlyEnabledForApprovedStatus() {
        #expect(!LaunchAtLoginStatus.notRegistered.isEnabled)
        #expect(LaunchAtLoginStatus.enabled.isEnabled)
        #expect(!LaunchAtLoginStatus.requiresApproval.isEnabled)
        #expect(!LaunchAtLoginStatus.notFound.isEnabled)
    }

    @Test
    func loginItemActionHidesTheButtonWhenActive() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(model.launchAtLoginActionTitle == "Turn on")
        model.performLaunchAtLoginAction()

        #expect(loginItem.registerCount == 1)
        #expect(model.launchAtLoginStatus == .enabled)
        #expect(model.launchAtLoginActionTitle == nil)

        model.performLaunchAtLoginAction()

        #expect(loginItem.openLoginItemsCount == 0)
        #expect(model.launchAtLoginStatus == .enabled)
    }

    @Test
    func notFoundLoginItemCanBeRegistered() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notFound)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(model.launchAtLoginActionTitle == "Turn on")
        model.performLaunchAtLoginAction()

        #expect(loginItem.registerCount == 1)
        #expect(loginItem.openLoginItemsCount == 0)
        #expect(model.launchAtLoginStatus == .enabled)
        #expect(model.launchAtLoginActionTitle == nil)
    }

    @Test
    func approvalRequiredOpensSystemSettings() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .requiresApproval)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        #expect(model.launchAtLoginActionTitle == "Open Login Items…")
        model.performLaunchAtLoginAction()

        #expect(loginItem.openLoginItemsCount == 1)
        #expect(loginItem.registerCount == 0)
    }

    @Test
    func registeringUpdatesTheStateFromTheSystemService() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        model.performLaunchAtLoginAction()

        #expect(loginItem.registerCount == 1)
        #expect(model.launchAtLoginStatus == .enabled)
        #expect(model.launchAtLoginIsEnabled)
        #expect(model.launchAtLoginErrorMessage == nil)
    }

    @Test
    func pendingApprovalIsNotReportedAsARegistrationError() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        loginItem.statusAfterRegister = .requiresApproval
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        model.performLaunchAtLoginAction()

        #expect(model.launchAtLoginStatus == .requiresApproval)
        #expect(model.launchAtLoginErrorMessage == nil)
    }

    @Test
    func registrationErrorIsShownAndSystemStatusRemainsOff() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        loginItem.registerError = FakeLaunchAtLoginError.registration
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        model.performLaunchAtLoginAction()

        #expect(model.launchAtLoginStatus == .notRegistered)
        #expect(!model.launchAtLoginIsEnabled)
        #expect(model.launchAtLoginErrorMessage == "Unable to register.")
    }

    @Test
    func registrationErrorIsShownWhenLoginItemIsNotFound() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notFound)
        loginItem.registerError = FakeLaunchAtLoginError.registration
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        model.performLaunchAtLoginAction()

        #expect(model.launchAtLoginStatus == .notFound)
        #expect(model.launchAtLoginActionTitle == "Turn on")
        #expect(model.launchAtLoginErrorMessage == "Unable to register.")
    }

    @Test
    func refreshingLoginItemStatusClearsAnOldError() {
        let accessibility = FakeAccessibilityTrustProvider(isTrusted: true)
        let loginItem = FakeLaunchAtLoginManager(status: .notRegistered)
        loginItem.registerError = FakeLaunchAtLoginError.registration
        let model = GeneralSettingsModel(accessibility: accessibility, loginItem: loginItem)

        model.performLaunchAtLoginAction()
        model.refreshLoginItemStatus()

        #expect(model.launchAtLoginErrorMessage == nil)
    }
}

@MainActor
private final class FakeAccessibilityTrustProvider: AccessibilityTrustProviding {
    var isTrustedValue: Bool
    var requestCount = 0

    init(isTrusted: Bool) {
        isTrustedValue = isTrusted
    }

    func isTrusted() -> Bool {
        isTrustedValue
    }

    func requestAccess() -> Bool {
        requestCount += 1
        return isTrustedValue
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus = .enabled
    var registerError: Error?
    var registerCount = 0
    var openLoginItemsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister
    }

    func openLoginItems() {
        openLoginItemsCount += 1
    }
}

private enum FakeLaunchAtLoginError: LocalizedError {
    case registration

    var errorDescription: String? {
        "Unable to register."
    }
}
