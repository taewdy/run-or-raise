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

        #expect(viewModel.results == [terminal])
        #expect(viewModel.selectedCommandID == terminal.id)
    }

    @Test("running selected command delegates launch and closes palette")
    func runSelectedCommandLaunchesCommand() {
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let launcher = RecordingWorkspaceLauncher()
        var closeCount = 0
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder]),
            launcher: launcher,
            onCommandRun: { closeCount += 1 }
        )

        viewModel.runSelectedCommand()

        #expect(launcher.openedCommands == [finder])
        #expect(closeCount == 1)
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
        #expect(viewModel.results == [finder, terminal])
    }
}

@MainActor
private final class RecordingWorkspaceLauncher: WorkspaceLaunching {
    private(set) var openedCommands: [LauncherCommand] = []

    func openOrRaise(_ command: LauncherCommand) {
        openedCommands.append(command)
    }
}
