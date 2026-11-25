import Testing
@testable import Kaygan

struct AppMenuNavigatorTests {
    @Test
    func navigationModifiersRejectShiftOptionAndNoCommand() {
        #expect(AppMenuNavigator.acceptsModifiers(0))
        #expect(AppMenuNavigator.acceptsModifiers(4))
        #expect(!AppMenuNavigator.acceptsModifiers(1))
        #expect(!AppMenuNavigator.acceptsModifiers(2))
        #expect(!AppMenuNavigator.acceptsModifiers(8))
        #expect(!AppMenuNavigator.acceptsModifiers(12))
    }
}
