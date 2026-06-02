import Testing
@testable import RunOrRaiseApp

@Suite("Command palette keyboard handling")
struct CommandPaletteKeyboardTests {
    @Test("return keys submit the selected command")
    func returnKeysSubmitSelectedCommand() {
        #expect(PaletteKey(keyCode: 36) == .submit)
        #expect(PaletteKey(keyCode: 76) == .submit)
    }
}
