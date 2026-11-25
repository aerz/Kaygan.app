enum SideButtonTestState: Equatable {
    case unavailable
    case detecting
    case scroll
    case navigationOff
    case back
    case forward
    case unused
    case idle

    static func resolve(
        detectedButton: Int?,
        isCapturing: Bool,
        isCaptureUnavailable: Bool,
        scrollButton: Int,
        navigationEnabled: Bool,
        reverseNavigation: Bool
    ) -> Self {
        if isCaptureUnavailable { return .unavailable }
        if isCapturing { return .detecting }
        guard let detectedButton else { return .idle }
        if scrollButton != 0, detectedButton == scrollButton { return .scroll }
        guard (4...5).contains(detectedButton) else { return .unused }
        guard navigationEnabled else { return .navigationOff }
        let goesBack = (detectedButton == 4) != reverseNavigation
        return goesBack ? .back : .forward
    }
}
