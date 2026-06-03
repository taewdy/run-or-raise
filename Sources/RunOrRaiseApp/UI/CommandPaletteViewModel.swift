import Foundation

struct CommandPaletteResultItem: Identifiable, Equatable {
    let id: LauncherCommand.ID
    let title: String
    let subtitle: String
    let badgeText: String
    let targetDescription: String
    let resultType: CommandResultType
    let activationTarget: CommandActivationTarget
    let matchedRanges: [CommandMatchedRange]
}

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = "" {
        didSet { updateResults() }
    }
    @Published private(set) var results: [CommandSearchResult]
    @Published var selectedCommandID: LauncherCommand.ID?
    @Published private(set) var resultsRevision = 0
    @Published private(set) var selectionRevision = 0
    @Published private(set) var isLoading = false
    @Published private(set) var launchMessage: String?

    private let commandIndex: CommandIndex
    private let launcher: WorkspaceLaunching
    private let onCommandRun: () -> Void
    private let onClose: () -> Void
    private let refreshFreshnessInterval: TimeInterval
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var currentApplication: CurrentApplicationContext?
    private var lastRefreshDate: Date?

    init(
        commandIndex: CommandIndex,
        launcher: WorkspaceLaunching,
        onCommandRun: @escaping () -> Void,
        onClose: @escaping () -> Void = {},
        refreshFreshnessInterval: TimeInterval = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.commandIndex = commandIndex
        self.launcher = launcher
        self.onCommandRun = onCommandRun
        self.onClose = onClose
        self.refreshFreshnessInterval = refreshFreshnessInterval
        self.now = now
        self.results = commandIndex.searchResults("")
        self.selectedCommandID = results.first?.id
    }

    var resultItems: [CommandPaletteResultItem] {
        results.map(CommandPaletteResultItem.init)
    }

    var emptyStateText: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No apps or windows indexed"
        }
        return "No matches for \"\(query)\""
    }

    var shouldShowResults: Bool {
        !results.isEmpty
    }

    var shouldShowLoadingState: Bool {
        isLoading && results.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowEmptyState: Bool {
        !shouldShowLoadingState && results.isEmpty
    }

    var shouldShowRefreshIndicator: Bool {
        isLoading && !results.isEmpty
    }

    func paletteOpened(currentApplication: CurrentApplicationContext? = nil) {
        self.currentApplication = currentApplication
        refreshTask?.cancel()
        resetQueryAndResults()
        let hasVisibleResults = !results.isEmpty
        isLoading = !hasVisibleResults

        guard shouldRefreshOnOpen(hasVisibleResults: hasVisibleResults) else {
            refreshTask = nil
            isLoading = false
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCommandData(generation: generation)
        }
    }

    private func shouldRefreshOnOpen(hasVisibleResults: Bool) -> Bool {
        guard hasVisibleResults, let lastRefreshDate else {
            return true
        }
        return now().timeIntervalSince(lastRefreshDate) >= refreshFreshnessInterval
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        isLoading = false
    }

    func reset() {
        resetQueryAndResults()
    }

    func selectNext() {
        moveSelection(by: 1)
    }

    func selectPrevious() {
        moveSelection(by: -1)
    }

    func runSelectedCommand() async {
        guard let selectedCommand else { return }
        let result = await launcher.openOrRaise(selectedCommand)
        launchMessage = result.userMessage
        guard result.didCompleteSelection else { return }

        commandIndex.recordSelection(selectedCommand)
        onCommandRun()
    }

    func close() {
        onClose()
    }

    private var selectedCommand: LauncherCommand? {
        (results.first { $0.id == selectedCommandID } ?? results.first)?.command
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            selectedCommandID = nil
            return
        }

        let currentIndex = selectedCommandID.flatMap { selectedID in
            results.firstIndex { $0.id == selectedID }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        guard nextIndex != currentIndex else { return }

        selectedCommandID = results[nextIndex].id
        selectionRevision += 1
    }

    private func updateResults() {
        updateResults(preservingSelection: false)
    }

    private func updateResults(preservingSelection: Bool) {
        let previousSelection = selectedCommandID
        let previousSelectionIdentity = selectedCommand?.usageIdentity
        launchMessage = nil
        results = commandIndex.searchResults(query, currentApplication: currentApplication)
        if preservingSelection,
           let preservedSelectionID = preservedSelectionID(
               matching: previousSelection,
               identity: previousSelectionIdentity
           ) {
            selectedCommandID = preservedSelectionID
        } else {
            selectedCommandID = results.first?.id
        }
        resultsRevision += 1
    }

    private func preservedSelectionID(
        matching previousSelection: LauncherCommand.ID?,
        identity previousSelectionIdentity: String?
    ) -> LauncherCommand.ID? {
        if let previousSelection,
           results.contains(where: { $0.id == previousSelection }) {
            return previousSelection
        }

        guard let previousSelectionIdentity else { return nil }
        return results.first {
            $0.command.usageIdentity == previousSelectionIdentity
        }?.id
    }

    private func resetQueryAndResults() {
        if query.isEmpty {
            updateResults()
        } else {
            query = ""
        }
    }

    private func refreshCommandData(generation: Int) async {
        let refreshedCommands = await Task.detached(priority: .userInitiated) { [commandIndex] in
            commandIndex.refreshedCommands()
        }.value

        guard !Task.isCancelled, generation == refreshGeneration else { return }
        commandIndex.replaceCommands(with: refreshedCommands)
        lastRefreshDate = now()
        updateResults(preservingSelection: true)
        isLoading = false
        refreshTask = nil
    }
}

private extension CommandPaletteResultItem {
    init(result: CommandSearchResult) {
        let command = result.command
        self.init(
            id: command.id,
            title: command.title,
            subtitle: command.subtitle,
            badgeText: command.resultType.paletteBadgeText,
            targetDescription: command.resultType.paletteTargetDescription,
            resultType: command.resultType,
            activationTarget: command.activationTarget,
            matchedRanges: result.matchedRanges
        )
    }
}

private extension CommandResultType {
    var paletteBadgeText: String {
        switch self {
        case .installedApplication:
            return "APP"
        case .runningApplication:
            return "RUNNING"
        case .runningWindow:
            return "WINDOW"
        }
    }

    var paletteTargetDescription: String {
        switch self {
        case .installedApplication:
            return "Open application"
        case .runningApplication:
            return "Raise running app"
        case .runningWindow:
            return "Raise window"
        }
    }
}
