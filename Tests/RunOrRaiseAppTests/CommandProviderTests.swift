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

    @Test("installed app discovery persists cache")
    func installedAppDiscoveryPersistsCache() throws {
        let directory = try makeTemporaryDirectory()
        let appURL = directory.appending(path: "Example.app", directoryHint: .isDirectory)
        try makeApplicationBundle(
            at: appURL,
            bundleIdentifier: "com.example.Example",
            displayName: "Example"
        )
        let cache = RecordingInstalledApplicationCommandCache()

        let commands = InstalledApplicationCommandProvider(
            applicationDirectories: [directory],
            cache: cache
        ).commands()

        #expect(cache.savedCommands == commands)
    }

    @Test("installed app provider falls back to cached index when discovery is empty")
    func installedAppProviderFallsBackToCache() {
        let cached = LauncherCommand(
            title: "Cached",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.Cached",
            resultType: .installedApplication,
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.Cached",
                applicationURL: URL(fileURLWithPath: "/Applications/Cached.app")
            )
        )
        let cache = RecordingInstalledApplicationCommandCache(cachedCommands: [cached])

        let commands = InstalledApplicationCommandProvider(
            applicationDirectories: [],
            cache: cache
        ).commands()

        #expect(commands == [cached])
        #expect(cache.savedCommands.isEmpty)
    }

    @Test("user defaults installed app cache persists commands")
    func userDefaultsInstalledAppCachePersistsCommands() throws {
        let suiteName = "RunOrRaiseAppTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let command = LauncherCommand(
            title: "Cached",
            subtitle: "Installed app",
            executableName: "Cached",
            bundleIdentifier: "com.example.Cached",
            resultType: .installedApplication,
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.Cached",
                applicationURL: URL(fileURLWithPath: "/Applications/Cached.app")
            )
        )
        let firstCache = UserDefaultsInstalledApplicationCommandCache(
            userDefaults: userDefaults,
            key: "installed"
        )

        firstCache.saveCommands([command])
        let secondCache = UserDefaultsInstalledApplicationCommandCache(
            userDefaults: userDefaults,
            key: "installed"
        )

        #expect(secondCache.loadCommands().map(\.title) == ["Cached"])
        #expect(secondCache.loadCommands().first?.bundleIdentifier == "com.example.Cached")
        #expect(secondCache.loadCommands().first?.executableName == "Cached")
        #expect(secondCache.loadCommands().first?.activationTarget == command.activationTarget)
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

    @Test("running window snapshots fall back to accessibility titles when CoreGraphics omits titles")
    func runningWindowSnapshotsUseAccessibilityTitles() {
        let snapshots = RunningWindowCommandProvider.snapshots(
            from: [
                [
                    kCGWindowOwnerPID as String: 101,
                    kCGWindowLayer as String: 0,
                    kCGWindowOwnerName as String: "Code",
                    kCGWindowNumber as String: 202
                ]
            ],
            accessibilityWindows: { processIdentifier in
                #expect(processIdentifier == 101)
                return [
                    RunningAccessibilityWindowSnapshot(
                        windowIdentifier: 202,
                        title: "AppCoordinator.swift - run-or-raise"
                    )
                ]
            }
        )

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.appName == "Code")
        #expect(snapshots.first?.processIdentifier == 101)
        #expect(snapshots.first?.windowIdentifier == 202)
        #expect(snapshots.first?.title == "AppCoordinator.swift - run-or-raise")
    }

    @Test("running window snapshots include accessibility windows without CoreGraphics identifiers")
    func runningWindowSnapshotsIncludeAccessibilityOnlyTitles() {
        let snapshots = RunningWindowCommandProvider.snapshots(
            from: [
                [
                    kCGWindowOwnerPID as String: 101,
                    kCGWindowLayer as String: 0,
                    kCGWindowOwnerName as String: "Code",
                    kCGWindowNumber as String: 202
                ]
            ],
            accessibilityWindows: { processIdentifier in
                #expect(processIdentifier == 101)
                return [
                    RunningAccessibilityWindowSnapshot(
                        windowIdentifier: nil,
                        title: "Package.swift - run-or-raise"
                    )
                ]
            }
        )

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.appName == "Code")
        #expect(snapshots.first?.processIdentifier == 101)
        #expect(snapshots.first?.windowIdentifier == nil)
        #expect(snapshots.first?.title == "Package.swift - run-or-raise")
    }

    @Test("running window snapshots include accessibility windows from running apps without CoreGraphics windows")
    func runningWindowSnapshotsIncludeNonCurrentRunningAppWindows() {
        let snapshots = RunningWindowCommandProvider.snapshots(
            from: [],
            runningApplications: [
                RunningApplicationSnapshot(
                    localizedName: "Code",
                    bundleIdentifier: "com.microsoft.VSCode",
                    processIdentifier: 101
                )
            ],
            accessibilityWindows: { processIdentifier in
                #expect(processIdentifier == 101)
                return [
                    RunningAccessibilityWindowSnapshot(
                        windowIdentifier: nil,
                        title: "Hidden Project"
                    )
                ]
            }
        )

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.appName == "Code")
        #expect(snapshots.first?.bundleIdentifier == "com.microsoft.VSCode")
        #expect(snapshots.first?.processIdentifier == 101)
        #expect(snapshots.first?.windowIdentifier == nil)
        #expect(snapshots.first?.title == "Hidden Project")
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

private final class RecordingInstalledApplicationCommandCache: InstalledApplicationCommandCaching {
    private let cachedCommands: [LauncherCommand]
    private(set) var savedCommands: [LauncherCommand] = []

    init(cachedCommands: [LauncherCommand] = []) {
        self.cachedCommands = cachedCommands
    }

    func loadCommands() -> [LauncherCommand] {
        cachedCommands
    }

    func saveCommands(_ commands: [LauncherCommand]) {
        savedCommands = commands
    }
}
