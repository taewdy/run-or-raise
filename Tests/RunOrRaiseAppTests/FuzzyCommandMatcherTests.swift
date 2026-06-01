import Testing
@testable import RunOrRaiseApp

@Suite("Fuzzy command matching")
struct FuzzyCommandMatcherTests {
    private let commands = [
        LauncherCommand(title: "Finder", subtitle: "Open or raise Finder"),
        LauncherCommand(title: "System Settings", subtitle: "Open macOS settings"),
        LauncherCommand(title: "Terminal", subtitle: "Open or raise Terminal")
    ]

    @Test("empty query returns every command in index order")
    func emptyQueryReturnsAllCommands() {
        let results = FuzzyCommandMatcher(commands: commands).search("")

        #expect(results.map(\.title) == ["Finder", "System Settings", "Terminal"])
    }

    @Test("prefix matches rank before fuzzy matches")
    func prefixMatchesRankFirst() {
        let results = FuzzyCommandMatcher(commands: commands).search("term")

        #expect(results.first?.title == "Terminal")
    }

    @Test("case and diacritic differences are ignored")
    func normalizesQuery() {
        let accented = commands + [
            LauncherCommand(title: "Résumé Editor", subtitle: "Edit resumes")
        ]

        let results = FuzzyCommandMatcher(commands: accented).search("resume")

        #expect(results.first?.title == "Résumé Editor")
    }

    @Test("non matching query returns no results")
    func nonMatchingQueryReturnsNoResults() {
        let results = FuzzyCommandMatcher(commands: commands).search("zzzz")

        #expect(results.isEmpty)
    }
}
