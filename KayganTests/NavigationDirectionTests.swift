import Testing
@testable import Kaygan

struct NavigationDirectionTests {
    @Test
    func englishMenuTitlesMatch() {
        #expect(NavigationDirection.back.matches(title: "Back"))
        #expect(NavigationDirection.back.matches(title: "Go Back"))
        #expect(NavigationDirection.forward.matches(title: "Forward"))
        #expect(NavigationDirection.forward.matches(title: "Go Forward"))
    }

    @Test
    func unrelatedTitlesDoNotMatch() {
        #expect(!NavigationDirection.back.matches(title: "Send Backward"))
        #expect(!NavigationDirection.back.matches(title: "Shift Left"))
        #expect(!NavigationDirection.forward.matches(title: "Forward Delete"))
        #expect(!NavigationDirection.forward.matches(title: "Back"))
    }

    @Test
    func trailingEllipsisIsIgnored() {
        #expect(NavigationDirection.back.matches(title: "Back…"))
        #expect(NavigationDirection.forward.matches(title: "Forward..."))
    }

    @Test
    func surroundingWhitespaceAndCaseAreIgnored() {
        #expect(NavigationDirection.back.matches(title: " GO BACK "))
        #expect(NavigationDirection.forward.matches(title: " Forward "))
    }

    @Test
    func ellipsisAfterWhitespaceIsIgnored() {
        #expect(NavigationDirection.back.matches(title: "Back …"))
    }

    @Test
    func aPlainPeriodDoesNotMatch() {
        #expect(!NavigationDirection.back.matches(title: "Back."))
    }

    @Test
    func backUsesLeftSwipeDirection() {
        #expect(NavigationEngine.swipeGestureDirection(for: .back) == 4)
        #expect(NavigationEngine.swipeGestureDirection(for: .forward) == 8)
    }
}
