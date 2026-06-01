import CoreGraphics
import Foundation
import Testing
@testable import RunOrRaiseApp

@Suite("Command providers")
struct CommandProviderTests {
    @Test("installed apps are discovered from application directories")
    func installedAppsAreDiscovered() throws {
        let directory = try makeTemporaryDirectory()
        let appURL = directory.appending(path: "Example.app", directoryHint: .isDirectory)
        try makeApplicationBundle(
            at: appURL,
            bundleIdentifier: "com.example.Example",
            displayName: "Example"
        )

        let commands = InstalledApplicationCommandProvider(
            applicationDirectories: [directory]
        ).commands()

        #expect(commands.count == 1)
        #expect(commands.first?.title == "Example")
        #expect(commands.first?.bundleIdentifier == "com.example.Example")
        #expect(commands.first?.resultType == .installedApplication)
        guard case .installedApplication(let bundleIdentifier, let applicationURL) = commands.first?.activationTarget else {
            Issue.record("Expected installed application activation target")
            return
        }
        #expect(bundleIdentifier == "com.example.Example")
        #expect(applicationURL?.standardizedFileURL.path == appURL.standardizedFileURL.path)
    }

    @Test("running app commands include process activation metadata")
    func runningAppsIncludeActivationMetadata() {
        let commands = RunningApplicationCommandProvider(
            snapshots: {
                [
                    RunningApplicationSnapshot(
                        localizedName: "Terminal",
                        bundleIdentifier: "com.apple.Terminal",
                        processIdentifier: 42
                    )
                ]
            }
        ).commands()

        #expect(commands.count == 1)
        #expect(commands.first?.title == "Terminal")
        #expect(commands.first?.subtitle == "Running app")
        #expect(commands.first?.bundleIdentifier == "com.apple.Terminal")
        #expect(commands.first?.resultType == .runningApplication)
        #expect(
            commands.first?.activationTarget == .runningApplication(
                bundleIdentifier: "com.apple.Terminal",
                processIdentifier: 42
            )
        )
    }

    @Test("running window commands include app and window activation metadata")
    func runningWindowsIncludeActivationMetadata() {
        let commands = RunningWindowCommandProvider(
            snapshots: {
                [
                    RunningWindowSnapshot(
                        appName: "Safari",
                        bundleIdentifier: "com.apple.Safari",
                        processIdentifier: 101,
                        windowIdentifier: 202,
                        title: "Documentation"
                    )
                ]
            }
        ).commands()

        #expect(commands.count == 1)
        #expect(commands.first?.title == "Documentation")
        #expect(commands.first?.subtitle == "Window in Safari")
        #expect(commands.first?.bundleIdentifier == "com.apple.Safari")
        #expect(commands.first?.resultType == .runningWindow)
        #expect(
            commands.first?.activationTarget == .runningWindow(
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: 101,
                windowIdentifier: 202
            )
        )
    }

    @Test("composite provider keeps windows and running app while suppressing equivalent installed apps")
    func compositeProviderDeduplicatesInstalledApps() {
        let installed = LauncherCommand(
            title: "Terminal",
            subtitle: "Installed app",
            bundleIdentifier: "com.apple.Terminal",
            resultType: .installedApplication,
            activationTarget: .installedApplication(
                bundleIdentifier: "com.apple.Terminal",
                applicationURL: URL(fileURLWithPath: "/Applications/Terminal.app")
            )
        )
        let duplicateInstalled = LauncherCommand(
            title: "Terminal Copy",
            subtitle: "Installed app",
            bundleIdentifier: "com.apple.Terminal",
            resultType: .installedApplication,
            activationTarget: .installedApplication(
                bundleIdentifier: "com.apple.Terminal",
                applicationURL: URL(fileURLWithPath: "/Users/test/Applications/Terminal.app")
            )
        )
        let running = LauncherCommand(
            title: "Terminal",
            subtitle: "Running app",
            bundleIdentifier: "com.apple.Terminal",
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: "com.apple.Terminal",
                processIdentifier: 42
            )
        )
        let window = LauncherCommand(
            title: "vim",
            subtitle: "Window in Terminal",
            bundleIdentifier: "com.apple.Terminal",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.apple.Terminal",
                processIdentifier: 42,
                windowIdentifier: 99
            )
        )

        let commands = CompositeCommandProvider(
            providers: [
                StaticCommandProvider(commands: [installed, duplicateInstalled]),
                StaticCommandProvider(commands: [running, window])
            ]
        ).commands()

        #expect(commands.map(\.resultType) == [.runningApplication, .runningWindow])
        #expect(commands.contains(window))
        #expect(commands.contains(running))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeApplicationBundle(
        at appURL: URL,
        bundleIdentifier: String,
        displayName: String
    ) throws {
        let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleExecutable": displayName
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appending(path: "Info.plist"))
    }
}

private final class StaticCommandProvider: CommandProviding {
    private let storedCommands: [LauncherCommand]

    init(commands: [LauncherCommand]) {
        self.storedCommands = commands
    }

    func commands() -> [LauncherCommand] {
        storedCommands
    }
}
