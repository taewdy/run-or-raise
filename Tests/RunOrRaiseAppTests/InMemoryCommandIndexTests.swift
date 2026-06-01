import Testing
@testable import RunOrRaiseApp

@Suite("In-memory command index")
struct InMemoryCommandIndexTests {
    @Test("reindex replaces commands with latest provider output")
    func reindexUsesProviderOutput() {
        let initial = LauncherCommand(title: "Initial", subtitle: "Before reindex")
        let refreshed = LauncherCommand(title: "Refreshed", subtitle: "After reindex")
        let provider = MutableCommandProvider(commands: [refreshed])
        let index = InMemoryCommandIndex(commands: [initial], provider: provider)

        index.reindex()

        #expect(index.allCommands == [refreshed])
    }
}

private final class MutableCommandProvider: CommandProviding {
    private let currentCommands: [LauncherCommand]

    init(commands: [LauncherCommand]) {
        self.currentCommands = commands
    }

    func commands() -> [LauncherCommand] {
        currentCommands
    }
}
