import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol WorkspaceLaunching {
    func openOrRaise(_ command: LauncherCommand) async -> WorkspaceLaunchResult
}

@MainActor
protocol WorkspaceApplicationLaunching {
    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationActivating]
    func runningApplication(processIdentifier: pid_t) -> RunningApplicationActivating?
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func applicationExists(at url: URL) -> Bool
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async -> Bool
}

@MainActor
protocol RunningApplicationActivating {
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplicationActivating {}

@MainActor
struct SystemWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationActivating] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    func runningApplication(processIdentifier: pid_t) -> RunningApplicationActivating? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func applicationExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }
}

enum WorkspaceLaunchResult: Equatable {
    case openedApplication
    case activatedApplication
    case focusedWindow
    case accessibilityPermissionRequired
    case targetUnavailable

    var didCompleteSelection: Bool {
        switch self {
        case .openedApplication, .activatedApplication, .focusedWindow:
            return true
        case .accessibilityPermissionRequired, .targetUnavailable:
            return false
        }
    }

    var userMessage: String? {
        switch self {
        case .openedApplication, .activatedApplication, .focusedWindow:
            return nil
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to focus that window."
        case .targetUnavailable:
            return "That app or window is no longer available."
        }
    }
}

enum CommandActivationDecision: Equatable {
    case openInstalledApplication(bundleIdentifier: String?, applicationURL: URL?)
    case activateRunningApplication(bundleIdentifier: String?, processIdentifier: pid_t)
    case focusRunningWindow(bundleIdentifier: String?, processIdentifier: pid_t, windowIdentifier: CGWindowID)
    case focusRunningWindowByTitle(bundleIdentifier: String?, processIdentifier: pid_t, title: String)
    case accessibilityPermissionRequired(bundleIdentifier: String?, processIdentifier: pid_t)
}

enum CommandActivationDecider {
    static func decision(
        for command: LauncherCommand,
        isAccessibilityTrusted: Bool
    ) -> CommandActivationDecision {
        switch command.activationTarget {
        case .installedApplication(let bundleIdentifier, let applicationURL):
            return .openInstalledApplication(bundleIdentifier: bundleIdentifier, applicationURL: applicationURL)
        case .runningApplication(let bundleIdentifier, let processIdentifier):
            return .activateRunningApplication(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            )
        case .runningWindow(let bundleIdentifier, let processIdentifier, let windowIdentifier):
            guard isAccessibilityTrusted else {
                return .accessibilityPermissionRequired(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier
                )
            }
            guard let windowIdentifier else {
                return .focusRunningWindowByTitle(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier,
                    title: command.title
                )
            }
            return .focusRunningWindow(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                windowIdentifier: windowIdentifier
            )
        }
    }
}

@MainActor
final class NSWorkspaceLauncher: WorkspaceLaunching {
    private let workspace: WorkspaceApplicationLaunching
    private let activationOptions: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]

    init(workspace: WorkspaceApplicationLaunching = SystemWorkspaceApplicationLauncher()) {
        self.workspace = workspace
    }

    func openOrRaise(_ command: LauncherCommand) async -> WorkspaceLaunchResult {
        switch CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: AXIsProcessTrusted()
        ) {
        case .openInstalledApplication(let bundleIdentifier, let applicationURL):
            return await openInstalledApplication(bundleIdentifier: bundleIdentifier, applicationURL: applicationURL)
        case .activateRunningApplication(let bundleIdentifier, let processIdentifier):
            return activateRunningApplication(bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier)
        case .accessibilityPermissionRequired(let bundleIdentifier, let processIdentifier):
            _ = activateRunningApplication(bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier)
            return .accessibilityPermissionRequired
        case .focusRunningWindow(let bundleIdentifier, let processIdentifier, let windowIdentifier):
            return focusRunningWindow(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                windowIdentifier: windowIdentifier
            )
        case .focusRunningWindowByTitle(let bundleIdentifier, let processIdentifier, let title):
            return focusRunningWindow(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                title: title
            )
        }
    }

    private func openInstalledApplication(
        bundleIdentifier: String?,
        applicationURL: URL?
    ) async -> WorkspaceLaunchResult {
        if let bundleIdentifier,
           let runningApp = workspace.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return runningApp.activate(options: activationOptions)
                ? .activatedApplication
                : .targetUnavailable
        }

        guard let appURL = applicationURL ?? bundleIdentifier.flatMap({
            workspace.urlForApplication(withBundleIdentifier: $0)
        }) else {
            return .targetUnavailable
        }

        guard workspace.applicationExists(at: appURL) else {
            return .targetUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await workspace.openApplication(at: appURL, configuration: configuration)
            ? .openedApplication
            : .targetUnavailable
    }

    private func activateRunningApplication(
        bundleIdentifier: String?,
        processIdentifier: pid_t
    ) -> WorkspaceLaunchResult {
        if let runningApp = workspace.runningApplication(processIdentifier: processIdentifier) {
            return runningApp.activate(options: activationOptions)
                ? .activatedApplication
                : .targetUnavailable
        }

        guard let bundleIdentifier,
              let runningApp = workspace.runningApplications(withBundleIdentifier: bundleIdentifier).first
        else {
            return .targetUnavailable
        }

        return runningApp.activate(options: activationOptions)
            ? .activatedApplication
            : .targetUnavailable
    }

    private func focusRunningWindow(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> WorkspaceLaunchResult {
        let activationResult = activateRunningApplication(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier
        )
        guard activationResult.didCompleteSelection else { return activationResult }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let windowElement = findWindow(
            windowIdentifier: windowIdentifier,
            in: applicationElement
        ) else {
            return .targetUnavailable
        }

        let raiseResult = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        let focusResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            windowElement
        )
        return raiseResult == .success && focusResult == .success
            ? .focusedWindow
            : .targetUnavailable
    }

    private func focusRunningWindow(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        title: String
    ) -> WorkspaceLaunchResult {
        let activationResult = activateRunningApplication(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier
        )
        guard activationResult.didCompleteSelection else { return activationResult }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let windowElement = findWindow(
            title: title,
            in: applicationElement
        ) else {
            return .targetUnavailable
        }

        let raiseResult = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        let focusResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            windowElement
        )
        return raiseResult == .success && focusResult == .success
            ? .focusedWindow
            : .targetUnavailable
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

    private func findWindow(title: String, in applicationElement: AXUIElement) -> AXUIElement? {
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )
        guard result == .success, let windows = rawWindows as? [AXUIElement] else { return nil }

        return windows.first { window in
            axTitle(window)?.trimmingCharacters(in: .whitespacesAndNewlines) == title
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

    private func axTitle(_ window: AXUIElement) -> String? {
        var rawTitle: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &rawTitle
        )
        guard result == .success else { return nil }
        return rawTitle as? String
    }
}
