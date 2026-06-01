import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import RunOrRaiseApp

@Suite("Workspace launcher")
struct WorkspaceLauncherTests {
    @Test("installed applications are opened")
    func installedApplicationDecision() {
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")
        let command = LauncherCommand(
            title: "Example",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.App",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.App",
                applicationURL: appURL
            )
        )

        #expect(CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: false
        ) == .openInstalledApplication(
            bundleIdentifier: "com.example.App",
            applicationURL: appURL
        ))
    }

    @Test("running applications are activated")
    func runningApplicationDecision() {
        let command = LauncherCommand(
            title: "Example",
            subtitle: "Running app",
            bundleIdentifier: "com.example.App",
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: "com.example.App",
                processIdentifier: 42
            )
        )

        #expect(CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: false
        ) == .activateRunningApplication(
            bundleIdentifier: "com.example.App",
            processIdentifier: 42
        ))
    }

    @Test("running windows require accessibility before exact focus")
    func runningWindowDecisionRequiresAccessibility() {
        let command = LauncherCommand(
            title: "Document",
            subtitle: "Window in Example",
            bundleIdentifier: "com.example.App",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.example.App",
                processIdentifier: 42,
                windowIdentifier: 99
            )
        )

        #expect(CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: false
        ) == .accessibilityPermissionRequired(
            bundleIdentifier: "com.example.App",
            processIdentifier: 42
        ))

        #expect(CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: true
        ) == .focusRunningWindow(
            bundleIdentifier: "com.example.App",
            processIdentifier: 42,
            windowIdentifier: 99
        ))
    }

    @Test("windows without window identifiers fall back to app activation")
    func runningWindowWithoutIdentifierActivatesApp() {
        let command = LauncherCommand(
            title: "Document",
            subtitle: "Window in Example",
            bundleIdentifier: "com.example.App",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.example.App",
                processIdentifier: 42,
                windowIdentifier: nil
            )
        )

        #expect(CommandActivationDecider.decision(
            for: command,
            isAccessibilityTrusted: true
        ) == .activateRunningApplication(
            bundleIdentifier: "com.example.App",
            processIdentifier: 42
        ))
    }

    @MainActor
    @Test("installed app selection activates running app ignoring other apps")
    func installedApplicationSelectionActivatesRunningAppIgnoringOtherApps() async {
        let app = StubRunningApplication()
        let workspace = StubWorkspaceApplicationLauncher()
        workspace.runningApplicationsByBundleIdentifier["com.example.App"] = [app]
        let launcher = NSWorkspaceLauncher(workspace: workspace)

        let result = await launcher.openOrRaise(LauncherCommand(
            title: "Example",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.App",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.App",
                applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
            )
        ))

        #expect(result == .activatedApplication)
        #expect(app.activationOptions == [.activateIgnoringOtherApps])
        #expect(workspace.openedApplicationURLs.isEmpty)
    }

    @MainActor
    @Test("running app selection activates process ignoring other apps")
    func runningApplicationSelectionActivatesProcessIgnoringOtherApps() async {
        let app = StubRunningApplication()
        let workspace = StubWorkspaceApplicationLauncher()
        workspace.runningApplicationsByProcessIdentifier[42] = app
        let launcher = NSWorkspaceLauncher(workspace: workspace)

        let result = await launcher.openOrRaise(LauncherCommand(
            title: "Example",
            subtitle: "Running app",
            bundleIdentifier: "com.example.App",
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: "com.example.App",
                processIdentifier: 42
            )
        ))

        #expect(result == .activatedApplication)
        #expect(app.activationOptions == [.activateIgnoringOtherApps])
    }

    @MainActor
    @Test("running app selection falls back to bundle activation ignoring other apps")
    func runningApplicationSelectionFallsBackToBundleActivationIgnoringOtherApps() async {
        let app = StubRunningApplication()
        let workspace = StubWorkspaceApplicationLauncher()
        workspace.runningApplicationsByBundleIdentifier["com.example.App"] = [app]
        let launcher = NSWorkspaceLauncher(workspace: workspace)

        let result = await launcher.openOrRaise(LauncherCommand(
            title: "Example",
            subtitle: "Running app",
            bundleIdentifier: "com.example.App",
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: "com.example.App",
                processIdentifier: 42
            )
        ))

        #expect(result == .activatedApplication)
        #expect(app.activationOptions == [.activateIgnoringOtherApps])
    }

    @MainActor
    @Test("stale installed application targets are unavailable")
    func staleInstalledApplicationTargetIsUnavailable() async {
        let appURL = URL(fileURLWithPath: "/Applications/Missing.app")
        let workspace = StubWorkspaceApplicationLauncher()
        workspace.existingApplicationURLs = []
        let launcher = NSWorkspaceLauncher(workspace: workspace)

        let result = await launcher.openOrRaise(LauncherCommand(
            title: "Missing",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.Missing",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.Missing",
                applicationURL: appURL
            )
        ))

        #expect(result == .targetUnavailable)
        #expect(workspace.openedApplicationURLs.isEmpty)
    }

    @MainActor
    @Test("installed application open failures are unavailable")
    func installedApplicationOpenFailureIsUnavailable() async {
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")
        let workspace = StubWorkspaceApplicationLauncher()
        workspace.existingApplicationURLs = [appURL]
        workspace.openApplicationResult = false
        let launcher = NSWorkspaceLauncher(workspace: workspace)

        let result = await launcher.openOrRaise(LauncherCommand(
            title: "Example",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.App",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.App",
                applicationURL: appURL
            )
        ))

        #expect(result == .targetUnavailable)
        #expect(workspace.openedApplicationURLs == [appURL])
    }
}

@MainActor
private final class StubWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    var existingApplicationURLs = Set<URL>()
    var openApplicationResult = true
    var runningApplicationsByBundleIdentifier: [String: [RunningApplicationActivating]] = [:]
    var runningApplicationsByProcessIdentifier: [pid_t: RunningApplicationActivating] = [:]
    private(set) var openedApplicationURLs: [URL] = []

    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationActivating] {
        runningApplicationsByBundleIdentifier[bundleIdentifier, default: []]
    }

    func runningApplication(processIdentifier: pid_t) -> RunningApplicationActivating? {
        runningApplicationsByProcessIdentifier[processIdentifier]
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        nil
    }

    func applicationExists(at url: URL) -> Bool {
        existingApplicationURLs.contains(url)
    }

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async -> Bool {
        openedApplicationURLs.append(url)
        return openApplicationResult
    }
}

@MainActor
private final class StubRunningApplication: RunningApplicationActivating {
    var activationResult = true
    private(set) var activationOptions: NSApplication.ActivationOptions?

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activationOptions = options
        return activationResult
    }
}
