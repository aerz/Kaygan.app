import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let button = "button"
        static let speed = "speed"
        static let reverse = "reverse"
        static let toggle = "toggle"
        static let navigationEnabled = "navigationEnabled"
        static let reverseNavigation = "reverseNavigation"
    }

    static let minSpeed: Int32 = 1
    static let maxSpeed: Int32 = 5
    static let defaultButton = 3
    static let defaultSpeed: Int32 = 3
    static let defaultReverse = false
    static let defaultToggle = false
    static let defaultNavigationEnabled = true
    static let defaultReverseNavigation = false

    var button: Int
    private(set) var isButtonConfigured: Bool
    var speed: Int32
    var reverse: Bool
    var toggle: Bool
    var navigationEnabled: Bool
    var reverseNavigation: Bool

    init(defaults: UserDefaults = .standard) {
        let savedButton = defaults.object(forKey: Key.button) as? Int
        if let savedButton, Self.isValidButton(savedButton) {
            button = savedButton
            isButtonConfigured = true
        } else {
            button = Self.defaultButton
            isButtonConfigured = false
        }
        let savedSpeed = Int32(clamping: defaults.object(forKey: Key.speed) as? Int ?? Int(Self.defaultSpeed))
        speed = min(max(savedSpeed, Self.minSpeed), Self.maxSpeed)
        reverse = (defaults.object(forKey: Key.reverse) as? NSNumber)?.boolValue ?? Self.defaultReverse
        toggle = (defaults.object(forKey: Key.toggle) as? NSNumber)?.boolValue ?? Self.defaultToggle
        navigationEnabled = (defaults.object(forKey: Key.navigationEnabled) as? NSNumber)?.boolValue ?? Self.defaultNavigationEnabled
        reverseNavigation = (defaults.object(forKey: Key.reverseNavigation) as? NSNumber)?.boolValue ?? Self.defaultReverseNavigation
    }

    func saveButton(to defaults: UserDefaults = .standard) {
        guard Self.isValidButton(button) else { return }
        defaults.set(button, forKey: Key.button)
        isButtonConfigured = true
    }

    func saveSpeed(to defaults: UserDefaults = .standard) {
        defaults.set(Int(speed), forKey: Key.speed)
    }

    func saveReverse(to defaults: UserDefaults = .standard) {
        defaults.set(reverse, forKey: Key.reverse)
    }

    func saveToggle(to defaults: UserDefaults = .standard) {
        defaults.set(toggle, forKey: Key.toggle)
    }

    func saveNavigationEnabled(to defaults: UserDefaults = .standard) {
        defaults.set(navigationEnabled, forKey: Key.navigationEnabled)
    }

    func saveReverseNavigation(to defaults: UserDefaults = .standard) {
        defaults.set(reverseNavigation, forKey: Key.reverseNavigation)
    }

    static func isValidButton(_ button: Int) -> Bool {
        button == 0 || (3...32).contains(button)
    }
}
