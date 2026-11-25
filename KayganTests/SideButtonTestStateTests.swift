import Testing
@testable import Kaygan

struct SideButtonTestStateTests {
    @Test
    func unavailableAndDetectingTakePriority() {
        #expect(state(detected: 4, unavailable: true) == .unavailable)
        #expect(state(detected: 4, capturing: true, unavailable: true) == .unavailable)
        #expect(state(detected: nil, capturing: true) == .detecting)
        #expect(state(detected: 4, capturing: true) == .detecting)
        #expect(state(detected: 4, capturing: true, scroll: 4) == .detecting)
    }

    @Test
    func idleWithoutDetectedButton() {
        #expect(state(detected: nil) == .idle)
    }

    @Test
    func scrollButtonTakesPriorityOverNavigation() {
        #expect(state(detected: 4, scroll: 4) == .scroll)
        #expect(state(detected: 4, scroll: 4, navigation: false) == .scroll)
        #expect(state(detected: 3, scroll: 3) == .scroll)
    }

    @Test
    func navigationOffOnlyAppliesToSideButtons() {
        #expect(state(detected: 4, navigation: false) == .navigationOff)
        #expect(state(detected: 4, scroll: 0, navigation: false) == .navigationOff)
        #expect(state(detected: 6, navigation: false) == .unused)
    }

    @Test
    func sideButtonActionsFollowReverseSetting() {
        #expect(state(detected: 4) == .back)
        #expect(state(detected: 4, reverse: true) == .forward)
        #expect(state(detected: 5) == .forward)
        #expect(state(detected: 5, reverse: true) == .back)
    }

    @Test
    func otherButtonsAreUnused() {
        #expect(state(detected: 6) == .unused)
        #expect(state(detected: 3, scroll: 4) == .unused)
    }

    private func state(
        detected: Int?,
        capturing: Bool = false,
        unavailable: Bool = false,
        scroll: Int = 3,
        navigation: Bool = true,
        reverse: Bool = false
    ) -> SideButtonTestState {
        SideButtonTestState.resolve(
            detectedButton: detected,
            isCapturing: capturing,
            isCaptureUnavailable: unavailable,
            scrollButton: scroll,
            navigationEnabled: navigation,
            reverseNavigation: reverse
        )
    }
}
