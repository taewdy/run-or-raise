import Foundation

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = "" {
        didSet { updateResults() }
    }
    @Published private(set) var results: [LauncherCommand]
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
        self.results = commandIndex.search("")
        self.selectedCommandID = results.first?.id
    }

    func reset() {
        query = ""
        updateResults()
    }

    func runSelectedCommand() {
        guard let selectedCommand else { return }
        launcher.openOrRaise(selectedCommand)
        onCommandRun()
    }

    private var selectedCommand: LauncherCommand? {
        results.first { $0.id == selectedCommandID } ?? results.first
    }

    private func updateResults() {
        results = commandIndex.search(query)
        selectedCommandID = results.first?.id
    }
}
