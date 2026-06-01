import AppKit
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
                recoveryAction: "Open Accessibility Settings"
            )
        ]
    }

    func requestPermission() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            openAccessibilitySettings()
        }
        return isTrusted
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
