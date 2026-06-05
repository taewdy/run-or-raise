import Testing
@testable import RunOrRaiseApp

@Suite("Command palette window controller")
struct CommandPaletteWindowControllerTests {
    @Test("hidden panel hotkey shows palette")
    func hiddenPanelHotkeyShowsPalette() {
        let action = CommandPaletteTogglePolicy.action(
            for: CommandPaletteWindowState(isVisible: false, isKey: false)
        )

        #expect(action == .show)
    }

    @Test("visible but inactive panel hotkey shows palette")
    func visibleInactivePanelHotkeyShowsPalette() {
        let action = CommandPaletteTogglePolicy.action(
            for: CommandPaletteWindowState(isVisible: true, isKey: false)
        )

        #expect(action == .show)
    }

    @Test("visible active panel hotkey cycles selection")
    func visibleActivePanelHotkeyCyclesSelection() {
        let action = CommandPaletteTogglePolicy.action(
            for: CommandPaletteWindowState(isVisible: true, isKey: true)
        )

        #expect(action == .selectNext)
    }
}
