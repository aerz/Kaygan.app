import Foundation
import Testing
@testable import Kaygan

@MainActor
struct AppExclusionTests {
    @Test
    func appExclusionsAreEmptyByDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettings(defaults: defaults).appExclusions.isEmpty)
    }

    @Test
    func appExclusionsPersistAndKeepIndependentFeatureOptions() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let exclusion = AppExclusion(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            applicationPath: "/Applications/Editor.app",
            scrollingDisabled: true,
            navigationDisabled: false
        )

        settings.saveAppExclusion(exclusion)
        let restored = AppSettings(defaults: defaults)

        #expect(restored.appExclusions == [exclusion])
        #expect(restored.scrollingIsDisabled(in: exclusion.bundleIdentifier))
        #expect(!restored.navigationIsDisabled(in: exclusion.bundleIdentifier))
    }

    @Test
    func savingAnExistingBundleIdentifierUpdatesItWithoutAddingADuplicate() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let original = exclusion(bundleIdentifier: "com.example.Editor")
        settings.saveAppExclusion(original)

        var edited = original
        edited.displayName = "Editor Pro"
        edited.scrollingDisabled = false
        edited.navigationDisabled = true
        settings.saveAppExclusion(edited)

        #expect(settings.appExclusions.count == 1)
        #expect(settings.appExclusions[0] == edited)
        #expect(!settings.scrollingIsDisabled(in: edited.bundleIdentifier))
        #expect(settings.navigationIsDisabled(in: edited.bundleIdentifier))
    }

    @Test
    func anUncommittedEditorDraftDoesNotChangeTheSavedRule() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let saved = exclusion(bundleIdentifier: "com.example.Editor")
        settings.saveAppExclusion(saved)

        var draft = saved
        draft.scrollingDisabled = false
        draft.navigationDisabled = false

        #expect(draft != saved)
        #expect(settings.appExclusions == [saved])
    }

    @Test
    func disablingNeitherFeatureKeepsTheEntryWithoutExcludingEitherOne() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var exclusion = exclusion(bundleIdentifier: "com.example.Editor")
        exclusion.scrollingDisabled = false
        exclusion.navigationDisabled = false

        settings.saveAppExclusion(exclusion)

        #expect(settings.appExclusions == [exclusion])
        #expect(!settings.scrollingIsDisabled(in: exclusion.bundleIdentifier))
        #expect(!settings.navigationIsDisabled(in: exclusion.bundleIdentifier))
    }

    @Test
    func removingAnAppDeletesItsRule() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let exclusion = exclusion(bundleIdentifier: "com.example.Editor")
        settings.saveAppExclusion(exclusion)

        settings.removeAppExclusion(bundleIdentifier: exclusion.bundleIdentifier)

        #expect(settings.appExclusions.isEmpty)
        #expect(!settings.scrollingIsDisabled(in: exclusion.bundleIdentifier))
        #expect(!settings.navigationIsDisabled(in: exclusion.bundleIdentifier))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "KayganTests.AppExclusionTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func exclusion(bundleIdentifier: String) -> AppExclusion {
        AppExclusion(
            bundleIdentifier: bundleIdentifier,
            displayName: "Editor",
            applicationPath: "/Applications/Editor.app",
            scrollingDisabled: true,
            navigationDisabled: true
        )
    }
}
