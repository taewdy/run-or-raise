import CoreGraphics
import Foundation

struct LauncherCommand: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let executableName: String?
    let bundleIdentifier: String?
    let resultType: CommandResultType
    let activationTarget: CommandActivationTarget

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        executableName: String? = nil,
        bundleIdentifier: String? = nil,
        resultType: CommandResultType = .installedApplication,
        activationTarget: CommandActivationTarget? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.executableName = executableName
        self.bundleIdentifier = bundleIdentifier
        self.resultType = resultType
        self.activationTarget = activationTarget ?? .installedApplication(
            bundleIdentifier: bundleIdentifier,
            applicationURL: nil
        )
    }
}

enum CommandResultType: Equatable {
    case installedApplication
    case runningApplication
    case runningWindow
}

enum CommandActivationTarget: Equatable {
    case installedApplication(bundleIdentifier: String?, applicationURL: URL?)
    case runningApplication(bundleIdentifier: String?, processIdentifier: pid_t)
    case runningWindow(bundleIdentifier: String?, processIdentifier: pid_t, windowIdentifier: CGWindowID?)
}

struct CurrentApplicationContext: Equatable, Sendable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t?

    init(bundleIdentifier: String?, processIdentifier: pid_t?) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

protocol CommandProviding {
    func commands() -> [LauncherCommand]
}

protocol CommandIndex: AnyObject, Sendable {
    var allCommands: [LauncherCommand] { get }
    func search(_ query: String) -> [LauncherCommand]
    func searchResults(_ query: String) -> [CommandSearchResult]
    func search(
        _ query: String,
        currentApplication: CurrentApplicationContext?
    ) -> [LauncherCommand]
    func searchResults(
        _ query: String,
        currentApplication: CurrentApplicationContext?
    ) -> [CommandSearchResult]
    func recordSelection(_ command: LauncherCommand)
    func refreshedCommands() -> [LauncherCommand]
    func replaceCommands(with commands: [LauncherCommand])
    func reindex()
}

extension CommandIndex {
    func reindex() {
        replaceCommands(with: refreshedCommands())
    }

    func search(_ query: String) -> [LauncherCommand] {
        search(query, currentApplication: nil)
    }

    func search(_ query: String, currentApplication: CurrentApplicationContext?) -> [LauncherCommand] {
        searchResults(query, currentApplication: currentApplication).map(\.command)
    }

    func searchResults(_ query: String) -> [CommandSearchResult] {
        searchResults(query, currentApplication: nil)
    }
}

final class InMemoryCommandIndex: CommandIndex, @unchecked Sendable {
    private let provider: CommandProviding?
    private let usageStore: CommandUsageStoring
    private let lock = NSLock()
    private var commands: [LauncherCommand]

    var allCommands: [LauncherCommand] {
        lock.withLock {
            commands
        }
    }

    init(
        commands: [LauncherCommand],
        provider: CommandProviding? = nil,
        usageStore: CommandUsageStoring = NoCommandUsageStore()
    ) {
        self.commands = commands
        self.provider = provider
        self.usageStore = usageStore
    }

    func searchResults(
        _ query: String,
        currentApplication: CurrentApplicationContext?
    ) -> [CommandSearchResult] {
        FuzzyCommandMatcher(
            commands: allCommands,
            usageStore: usageStore,
            currentApplication: currentApplication
        ).searchResults(query)
    }

    func recordSelection(_ command: LauncherCommand) {
        usageStore.recordSelection(for: command.usageIdentity, at: Date())
    }

    func refreshedCommands() -> [LauncherCommand] {
        guard let provider else { return allCommands }
        return provider.commands()
    }

    func replaceCommands(with commands: [LauncherCommand]) {
        lock.withLock {
            self.commands = commands
        }
    }
}

final class CompositeCommandProvider: CommandProviding {
    private let providers: [CommandProviding]

    init(providers: [CommandProviding]) {
        self.providers = providers
    }

    func commands() -> [LauncherCommand] {
        deduplicated(providers.flatMap { $0.commands() })
    }

    private func deduplicated(_ commands: [LauncherCommand]) -> [LauncherCommand] {
        let runningBundleIdentifiers = Set(
            commands
                .filter { $0.resultType == .runningApplication }
                .compactMap(\.bundleIdentifier)
        )
        var installedKeys = Set<InstalledApplicationKey>()
        var includedRunningBundleIdentifiers = Set<String>()
        var results: [LauncherCommand] = []

        for command in commands {
            switch command.resultType {
            case .runningWindow:
                results.append(command)
            case .runningApplication:
                guard let bundleIdentifier = command.bundleIdentifier else {
                    results.append(command)
                    continue
                }
                if includedRunningBundleIdentifiers.insert(bundleIdentifier).inserted {
                    results.append(command)
                }
            case .installedApplication:
                if shouldIncludeInstalledApplication(
                    command,
                    runningBundleIdentifiers: runningBundleIdentifiers,
                    installedKeys: &installedKeys
                ) {
                    results.append(command)
                }
            }
        }

        return results
    }

    private func shouldIncludeInstalledApplication(
        _ command: LauncherCommand,
        runningBundleIdentifiers: Set<String>,
        installedKeys: inout Set<InstalledApplicationKey>
    ) -> Bool {
        let key = InstalledApplicationKey(command: command)
        if let bundleIdentifier = command.bundleIdentifier, runningBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }
        return installedKeys.insert(key).inserted
    }
}

private struct InstalledApplicationKey: Hashable {
    private let value: String

    init(command: LauncherCommand) {
        if let bundleIdentifier = command.bundleIdentifier {
            value = "bundle:\(bundleIdentifier)"
            return
        }

        guard case .installedApplication(_, let applicationURL) = command.activationTarget else {
            value = "title:\(command.title)"
            return
        }

        value = "path:\(applicationURL?.standardizedFileURL.path ?? command.title)"
    }
}
