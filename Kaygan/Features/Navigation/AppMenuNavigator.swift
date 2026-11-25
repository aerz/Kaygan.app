@preconcurrency import ApplicationServices
import Foundation

enum AppMenuNavigator {
    private static let shiftOptionNoCommandMask = 0b1011

    static func acceptsModifiers(_ modifiers: Int) -> Bool {
        modifiers & shiftOptionNoCommandMask == 0
    }

    static func pressMenuItem(_ direction: NavigationDirection, in processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)

        guard let menuBar: AXUIElement = attribute(application, kAXMenuBarAttribute),
              let topLevelItems: [AXUIElement] = attribute(menuBar, kAXChildrenAttribute) else {
            KayganLogger.navigation.debug("No accessible menu bar for process \(processIdentifier)")
            return false
        }

        for topLevelItem in topLevelItems {
            guard let menus: [AXUIElement] = attribute(topLevelItem, kAXChildrenAttribute) else { continue }

            for menu in menus {
                guard let items: [AXUIElement] = attribute(menu, kAXChildrenAttribute) else { continue }

                for item in items {
                    let role: String = attribute(item, kAXRoleAttribute) ?? ""
                    guard role == kAXMenuItemRole else { continue }

                    let title: String = attribute(item, kAXTitleAttribute) ?? ""
                    guard direction.matches(title: title) else { continue }

                    guard let modifiers: Int = attribute(item, kAXMenuItemCmdModifiersAttribute),
                          Self.acceptsModifiers(modifiers),
                          let isEnabled: Bool = attribute(item, kAXEnabledAttribute),
                          isEnabled else {
                        continue
                    }

                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    guard result == .success else {
                        KayganLogger.navigation.warning(
                            "Could not press the \(direction.logName, privacy: .public) menu item: \(result.rawValue)"
                        )
                        return false
                    }

                    KayganLogger.navigation.info(
                        "Used the app menu for \(direction.logName, privacy: .public)"
                    )
                    return true
                }
            }
        }

        KayganLogger.navigation.debug(
            "No \(direction.logName, privacy: .public) menu item for process \(processIdentifier)"
        )
        return false
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
