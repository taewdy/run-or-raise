import AppKit
import Foundation

final class InstalledApplicationCommandProvider: CommandProviding {
    private let applicationDirectories: [URL]
    private let fileManager: FileManager
    private let cache: InstalledApplicationCommandCaching

    init(
        applicationDirectories: [URL]? = nil,
        fileManager: FileManager = .default,
        cache: InstalledApplicationCommandCaching = NoInstalledApplicationCommandCache()
    ) {
        self.applicationDirectories = applicationDirectories ?? Self.defaultApplicationDirectories(
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.cache = cache
    }

    func commands() -> [LauncherCommand] {
        let discoveredCommands = applicationURLs()
            .compactMap(makeCommand)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        guard !discoveredCommands.isEmpty else {
            return cache.loadCommands()
        }

        cache.saveCommands(discoveredCommands)
        return discoveredCommands
    }

    private static func defaultApplicationDirectories(fileManager: FileManager) -> [URL] {
        var directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]

        if let homeDirectory = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            directories.append(homeDirectory)
        }

        return directories
    }

    private func applicationURLs() -> [URL] {
        applicationDirectories.flatMap { directory in
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return [URL]()
            }

            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL, url.pathExtension == "app" else { return nil }
                return url
            }
        }
    }

    private func makeCommand(applicationURL: URL) -> LauncherCommand? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let title = displayName ?? bundleName ?? applicationURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle.bundleIdentifier

        return LauncherCommand(
            title: title,
            subtitle: "Installed app",
            executableName: executableName,
            bundleIdentifier: bundleIdentifier,
            resultType: .installedApplication,
            activationTarget: .installedApplication(
                bundleIdentifier: bundleIdentifier,
                applicationURL: applicationURL
            )
        )
    }
}

struct RunningApplicationSnapshot: Equatable {
    let localizedName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
}

final class RunningApplicationCommandProvider: CommandProviding {
    private let snapshots: () -> [RunningApplicationSnapshot]

    init(snapshots: @escaping () -> [RunningApplicationSnapshot] = RunningApplicationCommandProvider.currentSnapshots) {
        self.snapshots = snapshots
    }

    func commands() -> [LauncherCommand] {
        snapshots()
            .map(makeCommand)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    static func currentSnapshots() -> [RunningApplicationSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let localizedName = application.localizedName, !localizedName.isEmpty else {
                return nil
            }

            return RunningApplicationSnapshot(
                localizedName: localizedName,
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processIdentifier
            )
        }
    }

    private func makeCommand(_ snapshot: RunningApplicationSnapshot) -> LauncherCommand {
        LauncherCommand(
            title: snapshot.localizedName,
            subtitle: "Running app",
            bundleIdentifier: snapshot.bundleIdentifier,
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: snapshot.bundleIdentifier,
                processIdentifier: snapshot.processIdentifier
            )
        )
    }
}
