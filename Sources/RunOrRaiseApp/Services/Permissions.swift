import ApplicationServices
import Foundation

struct PermissionStatus: Equatable {
    let name: String
    let isGranted: Bool
    let recoveryAction: String
}

@MainActor
protocol PermissionStatusProviding {
    func currentStatuses() -> [PermissionStatus]
    func requestPermission() -> Bool
}

@MainActor
final class AccessibilityPermissionService: PermissionStatusProviding {
    func currentStatuses() -> [PermissionStatus] {
        [
            PermissionStatus(
                name: "Accessibility",
                isGranted: AXIsProcessTrusted(),
                recoveryAction: "Grant in System Settings"
            )
        ]
    }

    func requestPermission() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
