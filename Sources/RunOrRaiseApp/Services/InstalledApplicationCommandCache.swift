import Foundation

protocol InstalledApplicationCommandCaching: AnyObject {
    func loadCommands() -> [LauncherCommand]
    func saveCommands(_ commands: [LauncherCommand])
}

final class NoInstalledApplicationCommandCache: InstalledApplicationCommandCaching {
    func loadCommands() -> [LauncherCommand] {
        []
    }

    func saveCommands(_ commands: [LauncherCommand]) {}
}

final class UserDefaultsInstalledApplicationCommandCache: InstalledApplicationCommandCaching {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "InstalledApplicationIndex.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadCommands() -> [LauncherCommand] {
        guard
            let data = userDefaults.data(forKey: key),
            let records = try? JSONDecoder().decode([InstalledApplicationCacheRecord].self, from: data)
        else {
            return []
        }
        return records.map(\.command)
    }

    func saveCommands(_ commands: [LauncherCommand]) {
        let records = commands.compactMap(InstalledApplicationCacheRecord.init)
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: key)
    }
}

private struct InstalledApplicationCacheRecord: Codable {
    let title: String
    let subtitle: String
    let executableName: String?
    let bundleIdentifier: String?
    let applicationPath: String?

    init?(_ command: LauncherCommand) {
        guard case .installedApplication(let bundleIdentifier, let applicationURL) = command.activationTarget else {
            return nil
        }

        self.title = command.title
        self.subtitle = command.subtitle
        self.executableName = command.executableName
        self.bundleIdentifier = command.bundleIdentifier ?? bundleIdentifier
        self.applicationPath = applicationURL?.standardizedFileURL.path
    }

    var command: LauncherCommand {
        let applicationURL = applicationPath.map { URL(fileURLWithPath: $0) }
        return LauncherCommand(
            title: title,
            subtitle: subtitle,
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
