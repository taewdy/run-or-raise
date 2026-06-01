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

    @Test("running selected command records usage")
    func runSelectedCommandRecordsUsage() {
        let finder = LauncherCommand(title: "Finder", subtitle: "Open finder")
        let usageStore = RecordingCommandUsageStore()
        let viewModel = CommandPaletteViewModel(
            commandIndex: InMemoryCommandIndex(commands: [finder], usageStore: usageStore),
            launcher: RecordingWorkspaceLauncher(),
            onCommandRun: {}
        )

        viewModel.runSelectedCommand()

        #expect(usageStore.recordedIdentities == [finder.usageIdentity])
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
}

@MainActor
private final class RecordingWorkspaceLauncher: WorkspaceLaunching {
    private(set) var openedCommands: [LauncherCommand] = []

    func openOrRaise(_ command: LauncherCommand) {
        openedCommands.append(command)
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
