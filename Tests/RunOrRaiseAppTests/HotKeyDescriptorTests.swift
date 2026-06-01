import Carbon
import Testing
@testable import RunOrRaiseApp

@Suite("Hotkey descriptor")
struct HotKeyDescriptorTests {
    @Test("default hotkey is command shift space")
    func defaultHotKey() {
        #expect(HotKeyDescriptor.default.keyCode == UInt32(kVK_Space))
        #expect(HotKeyDescriptor.default.modifiers == UInt32(cmdKey | shiftKey))
        #expect(HotKeyDescriptor.default.displayText == "Command-Shift-Space")
    }
}
