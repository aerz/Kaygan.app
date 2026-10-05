import Testing
@testable import Kaygan

struct ScrollTapRecoveryPolicyTests {
    @Test
    func revokedAccessibilitySelectsStopAction() {
        #expect(
            ScrollTapRecoveryPolicy.action(
                tapKind: .primary,
                accessibilityTrusted: false,
                consecutiveTimeouts: 1,
                maximumTimeouts: 3
            ) == .stopForAccessibilityRevocation
        )
    }

    @Test
    func trustedTapRetriesAtTheLimit() {
        #expect(
            ScrollTapRecoveryPolicy.action(
                tapKind: .primary,
                accessibilityTrusted: true,
                consecutiveTimeouts: 3,
                maximumTimeouts: 3
            ) == .retryPrimaryTap
        )
    }

    @Test
    func trustedTapStopsAfterTheRetryLimit() {
        #expect(
            ScrollTapRecoveryPolicy.action(
                tapKind: .primary,
                accessibilityTrusted: true,
                consecutiveTimeouts: 4,
                maximumTimeouts: 3
            ) == .stopAfterRepeatedTimeouts
        )
    }

    @Test
    func disabledLatchTapCancelsToggleWithoutRetryingPrimaryTap() {
        #expect(
            ScrollTapRecoveryPolicy.action(
                tapKind: .latch,
                accessibilityTrusted: true,
                consecutiveTimeouts: 1,
                maximumTimeouts: 3
            ) == .cancelLatchedScroll
        )
    }
}
