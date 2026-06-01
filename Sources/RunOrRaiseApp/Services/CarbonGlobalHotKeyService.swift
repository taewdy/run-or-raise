import Carbon
import Foundation

@MainActor
final class CarbonGlobalHotKeyService: GlobalHotKeyRegistering {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (() -> Void)?

    func register(_ hotKey: HotKeyDescriptor, action: @escaping () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<CarbonGlobalHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    service.action?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            throw HotKeyRegistrationError.eventHandlerInstallFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(
                UInt32(UInt8(ascii: "R")) << 24
                    | UInt32(UInt8(ascii: "O")) << 16
                    | UInt32(UInt8(ascii: "R")) << 8
                    | UInt32(UInt8(ascii: "R"))
            ),
            id: 1
        )

        let registrationStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            unregisterEventHandler()
            throw HotKeyRegistrationError.registrationFailed(registrationStatus)
        }
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        unregisterEventHandler()
        action = nil
    }

    private func unregisterEventHandler() {
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }
}
