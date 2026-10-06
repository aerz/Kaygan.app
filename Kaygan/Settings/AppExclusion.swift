import Foundation

struct AppExclusion: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    var displayName: String
    var applicationPath: String
    var scrollingDisabled: Bool
    var navigationDisabled: Bool

    var id: String { bundleIdentifier }

    static func selectedApplication(at url: URL) -> AppExclusion? {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return AppExclusion(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationPath: url.path,
            scrollingDisabled: true,
            navigationDisabled: true
        )
    }
}
