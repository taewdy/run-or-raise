import Foundation

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = "" {
        didSet { updateResults() }
    }
    @Published private(set) var results: [CommandSearchResult]
    @Published var selectedCommandID: LauncherCommand.ID?

    private let commandIndex: CommandIndex
    private let launcher: WorkspaceLaunching
    private let onCommandRun: () -> Void

    init(
        commandIndex: CommandIndex,
        launcher: WorkspaceLaunching,
        onCommandRun: @escaping () -> Void
    ) {
        self.commandIndex = commandIndex
        self.launcher = launcher
        self.onCommandRun = onCommandRun
        self.results = commandIndex.searchResults("")
        self.selectedCommandID = results.first?.id
    }

    func reset() {
        query = ""
        updateResults()
    }

    func runSelectedCommand() {
        guard let selectedCommand else { return }
        launcher.openOrRaise(selectedCommand)
        commandIndex.recordSelection(selectedCommand)
        onCommandRun()
    }

    private var selectedCommand: LauncherCommand? {
        (results.first { $0.id == selectedCommandID } ?? results.first)?.command
    }

    private func updateResults() {
        results = commandIndex.searchResults(query)
        selectedCommandID = results.first?.id
    }
}
