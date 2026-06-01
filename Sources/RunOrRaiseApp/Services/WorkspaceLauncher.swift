import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol WorkspaceLaunching {
    func openOrRaise(_ command: LauncherCommand)
}

@MainActor
final class NSWorkspaceLauncher: WorkspaceLaunching {
    func openOrRaise(_ command: LauncherCommand) {
        switch command.activationTarget {
        case .installedApplication(let bundleIdentifier, let applicationURL):
            openInstalledApplication(bundleIdentifier: bundleIdentifier, applicationURL: applicationURL)
        case .runningApplication(let bundleIdentifier, let processIdentifier):
            activateRunningApplication(bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier)
        case .runningWindow(let bundleIdentifier, let processIdentifier, let windowIdentifier):
            focusRunningWindow(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                windowIdentifier: windowIdentifier
            )
        }
    }

    private func openInstalledApplication(bundleIdentifier: String?, applicationURL: URL?) {
        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier ?? ""
        ).first {
            runningApp.activate(options: [.activateIgnoringOtherApps])
            return
        }

        guard let appURL = applicationURL ?? bundleIdentifier.flatMap({
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func activateRunningApplication(bundleIdentifier: String?, processIdentifier: pid_t) {
        if let runningApp = NSRunningApplication(processIdentifier: processIdentifier) {
            runningApp.activate(options: [.activateIgnoringOtherApps])
            return
        }

        guard let bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private func focusRunningWindow(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID?
    ) {
        activateRunningApplication(bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier)
        guard let windowIdentifier, AXIsProcessTrusted() else { return }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let windowElement = findWindow(
            windowIdentifier: windowIdentifier,
            in: applicationElement
        ) else {
            return
        }

        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            windowElement
        )
    }

    private func findWindow(windowIdentifier: CGWindowID, in applicationElement: AXUIElement) -> AXUIElement? {
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )
        guard result == .success, let windows = rawWindows as? [AXUIElement] else { return nil }

        return windows.first { window in
            axWindowIdentifier(window) == windowIdentifier
        }
    }

    private func axWindowIdentifier(_ window: AXUIElement) -> CGWindowID? {
        var rawIdentifier: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            "AXWindowNumber" as CFString,
            &rawIdentifier
        )
        guard result == .success else { return nil }

        if let identifier = rawIdentifier as? CGWindowID {
            return identifier
        }
        if let identifier = rawIdentifier as? Int {
            return CGWindowID(identifier)
        }
        return nil
    }
}
