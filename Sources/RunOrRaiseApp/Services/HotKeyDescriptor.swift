import Carbon
import Foundation

struct HotKeyDescriptor: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayText: String

    static let `default` = HotKeyDescriptor(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey),
        displayText: "Command-Shift-Space"
    )
}

enum HotKeyRegistrationError: LocalizedError {
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallFailed(let status):
            return "Unable to install hotkey handler (OSStatus \(status))."
        case .registrationFailed(let status):
            return "Unable to register global hotkey (OSStatus \(status))."
        }
    }
}

@MainActor
protocol GlobalHotKeyRegistering {
    func register(_ hotKey: HotKeyDescriptor, action: @escaping () -> Void) throws
    func unregister()
}
