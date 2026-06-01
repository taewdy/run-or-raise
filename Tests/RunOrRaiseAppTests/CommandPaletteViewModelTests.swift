import Foundation
import Testing
@testable import RunOrRaiseApp

@MainActor
@Suite("Command palette view model")
struct CommandPaletteViewModelTests {
    @Test("updates results and selected command when query changes")
    func queryFiltersResults() {
        let terminal = LauncherCommand(title: "Terminal", subtitle: "Open terminal")
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder, terminal]),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.query = "term"

        #expect(viewModel.results.map(\.command) == [terminal])
        #expect(viewModel.selectedCommandID == terminal.id)
    }

    @Test("running selected command delegates launch and closes palette")
    func runSelectedCommandLaunchesCommand() async {
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let launcher = RecordingWorkspaceLauncher()
        var closeCount = 0
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder]),
            launcher: launcher,
            onCommandRun: { closeCount += 1 }
        )

        await viewModel.runSelectedCommand()

        #expect(launcher.openedCommands == [finder])
        #expect(closeCount == 1)
    }

    @Test("running selected command records usage")
    func runSelectedCommandRecordsUsage() async {
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let usageStore = RecordingCommandUsageStore()
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder], usageStore: usageStore),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        await viewModel.runSelectedCommand()

        #expect(usageStore.recordedIdentities == [finder.usageIdentity])
    }

    @Test("running selected command waits for launch before recording usage")
    func runSelectedCommandWaitsForLaunchBeforeRecordingUsage() async throws {
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let usageStore = RecordingCommandUsageStore()
        let launcher = RecordingWorkspaceLauncher()
        launcher.delayUntilResumed = true
        var closeCount = 0
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder], usageStore: usageStore),
            launcher: launcher,
            onCommandRun: { closeCount += 1 }
        )

        let runTask = Task { await viewModel.runSelectedCommand() }
        try await waitUntil {
            launcher.openedCommands == [finder]
        }

        #expect(usageStore.recordedIdentities.isEmpty)
        #expect(closeCount == 0)

        launcher.resume()
        await runTask.value

        #expect(usageStore.recordedIdentities == [finder.usageIdentity])
        #expect(closeCount == 1)
    }

    @Test("failed command activation leaves palette open and does not record usage")
    func failedCommandActivationDoesNotRecordUsage() async {
        let window = LauncherCommand(
            title: "Inbox",
            subtitle: "Window in Mail",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 100,
                windowIdentifier: 200
            )
        )
        let usageStore = RecordingCommandUsageStore()
        let launcher = RecordingWorkspaceLauncher()
        launcher.result = .accessibilityPermissionRequired
        var closeCount = 0
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [window], usageStore: usageStore),
            launcher: launcher,
            onCommandRun: { closeCount += 1 }
        )

        await viewModel.runSelectedCommand()

        #expect(launcher.openedCommands == [window])
        #expect(usageStore.recordedIdentities.isEmpty)
        #expect(closeCount == 0)
        #expect(viewModel.launchMessage == "Accessibility permission is required to focus that window.")
    }

    @Test("reset clears query and restores all results")
    func resetClearsQuery() {
        let terminal = LauncherCommand(title: "Terminal", subtitle: "Open terminal")
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder, terminal]),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.query = "term"
        viewModel.reset()

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.results.map(\.command) == [finder, terminal])
    }

    @Test("opening refreshes command data and exposes refreshed results")
    func paletteOpenedRefreshesCommandData() async throws {
        let initial = LauncherCommand(title: "Initial", subtitle: "Before reindex")
        let refreshed = LauncherCommand(title: "Refreshed", subtitle: "After reindex")
        let commandIndex = BlockingRefreshCommandIndex(initialCommands: [initial], refreshedCommands: [refreshed])
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )
        commandIndex.resetSearchTracking()

        viewModel.paletteOpened()

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.results.map(\.command) == [initial])
        #expect(viewModel.selectedCommandID == initial.id)
        #expect(viewModel.isLoading)
        #expect(commandIndex.searchQueries == [""])

        await Task.yield()
        #expect(commandIndex.waitUntilRefreshStarts())
        #expect(viewModel.isLoading)

        commandIndex.finishRefresh()
        try await waitUntil {
            viewModel.isLoading == false
        }

        #expect(viewModel.results.map(\.command) == [refreshed])
        #expect(viewModel.selectedCommandID == refreshed.id)
        #expect(commandIndex.searchQueries == ["", ""])
    }

    @Test("loading presentation keeps cached results visible during refresh")
    func loadingPresentationKeepsCachedResultsVisible() {
        let initial = LauncherCommand(title: "Initial", subtitle: "Before reindex")
        let commandIndex = BlockingRefreshCommandIndex(initialCommands: [initial], refreshedCommands: [])
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.paletteOpened()

        #expect(viewModel.shouldShowResults)
        #expect(viewModel.shouldShowRefreshIndicator)
        #expect(viewModel.shouldShowLoadingState == false)
        #expect(viewModel.shouldShowEmptyState == false)

        viewModel.query = "missing"

        #expect(viewModel.shouldShowResults == false)
        #expect(viewModel.shouldShowRefreshIndicator == false)
        #expect(viewModel.shouldShowLoadingState == false)
        #expect(viewModel.shouldShowEmptyState)

        viewModel.cancelRefresh()
        commandIndex.finishRefresh()
    }

    @Test("loading presentation uses blocking state only when no cached results exist")
    func loadingPresentationUsesBlockingStateOnlyWhenNoCachedResultsExist() {
        let commandIndex = BlockingRefreshCommandIndex(initialCommands: [], refreshedCommands: [])
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.paletteOpened()

        #expect(viewModel.shouldShowResults == false)
        #expect(viewModel.shouldShowRefreshIndicator == false)
        #expect(viewModel.shouldShowLoadingState)
        #expect(viewModel.shouldShowEmptyState == false)

        viewModel.cancelRefresh()
        commandIndex.finishRefresh()
    }

    @Test("canceling refresh does not commit stale command data")
    func cancelingRefreshDoesNotCommitStaleCommandData() async throws {
        let initial = LauncherCommand(title: "Initial", subtitle: "Before reindex")
        let staleRefresh = LauncherCommand(title: "Stale", subtitle: "Canceled refresh")
        let commandIndex = BlockingRefreshCommandIndex(initialCommands: [initial], refreshedCommands: [staleRefresh])
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.paletteOpened()

        await Task.yield()
        #expect(commandIndex.waitUntilRefreshStarts())

        viewModel.cancelRefresh()
        commandIndex.finishRefresh()

        try await waitUntil {
            commandIndex.completedRefreshCount == 1
        }

        #expect(viewModel.isLoading == false)
        #expect(commandIndex.allCommands == [initial])
        #expect(viewModel.results.map(\.command) == [initial])
        #expect(viewModel.selectedCommandID == initial.id)
    }

    @Test("superseded refresh cannot overwrite newer command data")
    func supersededRefreshCannotOverwriteNewerCommandData() async throws {
        let initial = LauncherCommand(title: "Initial", subtitle: "Before reindex")
        let staleRefresh = LauncherCommand(title: "Stale", subtitle: "First refresh")
        let currentRefresh = LauncherCommand(title: "Current", subtitle: "Second refresh")
        let commandIndex = SequencedRefreshCommandIndex(
            initialCommands: [initial],
            refreshSnapshots: [[staleRefresh], [currentRefresh]]
        )
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.paletteOpened()

        await Task.yield()
        #expect(commandIndex.waitUntilRefreshStarts(count: 1))

        viewModel.paletteOpened()

        await Task.yield()
        #expect(commandIndex.waitUntilRefreshStarts(count: 2))

        commandIndex.finishRefresh(number: 2)
        try await waitUntil {
            viewModel.results.map(\.command) == [currentRefresh]
        }

        commandIndex.finishRefresh(number: 1)
        try await waitUntil {
            commandIndex.completedRefreshCount == 2
        }

        #expect(commandIndex.allCommands == [currentRefresh])
        #expect(viewModel.results.map(\.command) == [currentRefresh])
        #expect(viewModel.selectedCommandID == currentRefresh.id)
        #expect(viewModel.isLoading == false)
    }

    @Test("keyboard navigation moves selection through results")
    func keyboardNavigationMovesSelection() {
        let first = LauncherCommand(title: "First", subtitle: "Installed app")
        let second = LauncherCommand(title: "Second", subtitle: "Running app")
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [first, second]),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.selectNext()
        #expect(viewModel.selectedCommandID == second.id)

        viewModel.selectNext()
        #expect(viewModel.selectedCommandID == first.id)

        viewModel.selectPrevious()
        #expect(viewModel.selectedCommandID == second.id)
    }

    @Test("closing delegates to close handler")
    func closeDelegatesToCloseHandler() {
        var closeCount = 0
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: []),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {},
            onClose: { closeCount += 1 }
        )

        viewModel.close()

        #expect(closeCount == 1)
    }

    @Test("view data distinguishes installed apps running apps and windows")
    func viewDataDistinguishesResultTypes() {
        let installed = LauncherCommand(title: "Mail", subtitle: "Installed app")
        let running = LauncherCommand(
            title: "Calendar",
            subtitle: "Running app",
            resultType: .runningApplication,
            activationTarget: .runningApplication(bundleIdentifier: nil, processIdentifier: 10)
        )
        let window = LauncherCommand(
            title: "Release Notes",
            subtitle: "Window in Notes",
            resultType: .runningWindow,
            activationTarget: .runningWindow(bundleIdentifier: nil, processIdentifier: 11, windowIdentifier: 12)
        )
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [installed, running, window]),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        #expect(viewModel.resultItems.map(\.badgeText) == ["APP", "RUNNING", "WINDOW"])
        #expect(viewModel.resultItems.map(\.targetDescription) == ["Open application", "Raise running app", "Raise window"])
        #expect(viewModel.resultItems[2].title == "Release Notes")
        #expect(viewModel.resultItems[2].subtitle == "Window in Notes")
    }

    @Test("empty state reflects whether a query is active")
    func emptyStateReflectsQuery() {
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: []),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        #expect(viewModel.emptyStateText == "No apps or windows indexed")

        viewModel.query = "nothing"

        #expect(viewModel.emptyStateText == "No matches for \"nothing\"")
    }
}

@MainActor
private final class RecordingWorkspaceLauncher: WorkspaceLaunching {
    private(set) var openedCommands: [LauncherCommand] = []
    var result: WorkspaceLaunchResult = .activatedApplication
    var delayUntilResumed = false
    private var continuation: CheckedContinuation<Void, Never>?

    func openOrRaise(_ command: LauncherCommand) async -> WorkspaceLaunchResult {
        openedCommands.append(command)
        if delayUntilResumed {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return result
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class RecordingCommandUsageStore: CommandUsageStoring {
    private(set) var recordedIdentities: [String] = []

    func usage(for identity: String) -> CommandUsage? {
        nil
    }

    func recordSelection(for identity: String, at date: Date) {
        recordedIdentities.append(identity)
    }
}

private final class BlockingRefreshCommandIndex: CommandIndex, @unchecked Sendable {
    private let lock = NSLock()
    private let refreshStarted = DispatchSemaphore(value: 0)
    private let refreshCanFinish = DispatchSemaphore(value: 0)
    private var commands: [LauncherCommand]
    private let nextCommands: [LauncherCommand]
    private var refreshCompletions = 0
    private var recordedSearchQueries: [String] = []

    var allCommands: [LauncherCommand] {
        lock.withLock {
            commands
        }
    }

    init(initialCommands: [LauncherCommand], refreshedCommands: [LauncherCommand]) {
        self.commands = initialCommands
        self.nextCommands = refreshedCommands
    }

    func search(_ query: String) -> [LauncherCommand] {
        searchResults(query).map(\.command)
    }

    func searchResults(_ query: String) -> [CommandSearchResult] {
        lock.withLock {
            recordedSearchQueries.append(query)
        }
        return FuzzyCommandMatcher(commands: allCommands).searchResults(query)
    }

    func recordSelection(_ command: LauncherCommand) {}

    func refreshedCommands() -> [LauncherCommand] {
        refreshStarted.signal()
        refreshCanFinish.wait()
        lock.withLock {
            refreshCompletions += 1
        }
        return nextCommands
    }

    func replaceCommands(with commands: [LauncherCommand]) {
        lock.withLock {
            self.commands = commands
        }
    }

    var completedRefreshCount: Int {
        lock.withLock {
            refreshCompletions
        }
    }

    var searchQueries: [String] {
        lock.withLock {
            recordedSearchQueries
        }
    }

    func resetSearchTracking() {
        lock.withLock {
            recordedSearchQueries = []
        }
    }

    func waitUntilRefreshStarts() -> Bool {
        refreshStarted.wait(timeout: .now() + 1) == .success
    }

    func finishRefresh() {
        refreshCanFinish.signal()
    }
}

private final class SequencedRefreshCommandIndex: CommandIndex, @unchecked Sendable {
    private let lock = NSLock()
    private let refreshStarted = DispatchSemaphore(value: 0)
    private let refreshSnapshots: [[LauncherCommand]]
    private let refreshFinishSignals: [DispatchSemaphore]
    private var commands: [LauncherCommand]
    private var startedRefreshCount = 0
    private var refreshCompletions = 0

    var allCommands: [LauncherCommand] {
        lock.withLock {
            commands
        }
    }

    init(initialCommands: [LauncherCommand], refreshSnapshots: [[LauncherCommand]]) {
        self.commands = initialCommands
        self.refreshSnapshots = refreshSnapshots
        self.refreshFinishSignals = refreshSnapshots.map { _ in DispatchSemaphore(value: 0) }
    }

    func search(_ query: String) -> [LauncherCommand] {
        searchResults(query).map(\.command)
    }

    func searchResults(_ query: String) -> [CommandSearchResult] {
        FuzzyCommandMatcher(commands: allCommands).searchResults(query)
    }

    func recordSelection(_ command: LauncherCommand) {}

    func refreshedCommands() -> [LauncherCommand] {
        let refreshNumber = lock.withLock {
            startedRefreshCount += 1
            return startedRefreshCount
        }
        refreshStarted.signal()
        refreshFinishSignals[refreshNumber - 1].wait()

        return lock.withLock {
            refreshCompletions += 1
            return refreshSnapshots[refreshNumber - 1]
        }
    }

    func replaceCommands(with commands: [LauncherCommand]) {
        lock.withLock {
            self.commands = commands
        }
    }

    var completedRefreshCount: Int {
        lock.withLock {
            refreshCompletions
        }
    }

    func waitUntilRefreshStarts(count: Int) -> Bool {
        let deadline = DispatchTime.now() + 1
        while true {
            if lock.withLock({ startedRefreshCount >= count }) {
                return true
            }
            guard refreshStarted.wait(timeout: deadline) == .success else {
                return false
            }
        }
    }

    func finishRefresh(number: Int) {
        refreshFinishSignals[number - 1].signal()
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let start = ContinuousClock.now
    while !condition() {
        if start.duration(to: .now) > timeout {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
