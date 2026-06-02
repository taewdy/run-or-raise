import Foundation
import Testing
@testable import RunOrRaiseApp

@Suite("Fuzzy command matching")
struct FuzzyCommandMatcherTests {
    private let commands = [
        LauncherCommand(title: "Finder", subtitle: "Open or raise Finder"),
        LauncherCommand(title: "System Settings", subtitle: "Open macOS settings"),
        LauncherCommand(title: "Terminal", subtitle: "Open or raise Terminal")
    ]

    @Test("empty query returns recently used commands first")
    func emptyQueryReturnsRecentlyUsedCommandsFirst() {
        let now = Date()
        let usageStore = FixtureCommandUsageStore(usages: [
            commands[2].usageIdentity: CommandUsage(
                selectionCount: 1,
                lastSelectedAt: now.addingTimeInterval(-60)
            )
        ])

        let results = FuzzyCommandMatcher(commands: commands, usageStore: usageStore).search("")

        #expect(results.map(\.title) == ["Terminal", "Finder", "System Settings"])
    }

    @Test("prefix matches rank before fuzzy matches")
    func prefixMatchesRankFirst() {
        let results = FuzzyCommandMatcher(commands: commands).search("term")

        #expect(results.first?.title == "Terminal")
    }

    @Test("ordered character matches return highlight ranges")
    func orderedCharacterMatchesReturnRanges() {
        let results = FuzzyCommandMatcher(commands: commands).searchResults("tmn")

        #expect(results.first?.command.title == "Terminal")
        #expect(results.first?.matchedRanges == [
            CommandMatchedRange(field: .title, location: 0, length: 1),
            CommandMatchedRange(field: .title, location: 3, length: 1),
            CommandMatchedRange(field: .title, location: 5, length: 1)
        ])
    }

    @Test("queries match bundle identifiers executable names and paths")
    func queriesMatchCommandMetadata() {
        let command = LauncherCommand(
            title: "Code",
            subtitle: "Installed app",
            executableName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.microsoft.VSCode",
                applicationURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
            )
        )
        let matcher = FuzzyCommandMatcher(commands: [command])

        #expect(matcher.search("microsoft").first == command)
        #expect(matcher.search("visual studio").first == command)
        #expect(matcher.search("applications/visual").first == command)
    }

    @Test("queries match combined app and window text")
    func queriesMatchCombinedAppAndWindowText() {
        let jidayWindow = LauncherCommand(
            title: "Jiday",
            subtitle: "Window in Code",
            bundleIdentifier: "com.microsoft.VSCode",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.microsoft.VSCode",
                processIdentifier: 42,
                windowIdentifier: nil
            )
        )
        let unrelatedWindow = LauncherCommand(
            title: "Jira",
            subtitle: "Window in Safari",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: 43,
                windowIdentifier: nil
            )
        )
        let matcher = FuzzyCommandMatcher(commands: [unrelatedWindow, jidayWindow])

        #expect(matcher.search("Code Jiday").first == jidayWindow)
        #expect(matcher.search("Jiday Code").first == jidayWindow)
    }

    @Test("combined matches return visible field highlight ranges")
    func combinedMatchesReturnVisibleFieldHighlightRanges() {
        let jidayWindow = LauncherCommand(
            title: "Jiday",
            subtitle: "Window in Code",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.microsoft.VSCode",
                processIdentifier: 42,
                windowIdentifier: nil
            )
        )

        let result = FuzzyCommandMatcher(commands: [jidayWindow]).searchResults("Code Jiday").first

        #expect(result?.command == jidayWindow)
        #expect(result?.matchedRanges.contains(CommandMatchedRange(field: .subtitle, location: 10, length: 4)) == true)
        #expect(result?.matchedRanges.contains(CommandMatchedRange(field: .title, location: 0, length: 5)) == true)
    }

    @Test("word and path boundary matches rank strongly")
    func boundaryMatchesRankStrongly() {
        let boundary = LauncherCommand(title: "Visual Studio Code", subtitle: "Installed app")
        let compact = LauncherCommand(title: "Vision Tools Code", subtitle: "Installed app")

        let results = FuzzyCommandMatcher(commands: [compact, boundary]).search("studio")

        #expect(results.first == boundary)
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

    @Test("usage frequency and recency can reorder similarly relevant matches")
    func usageReordersSimilarMatches() {
        let terminal = LauncherCommand(title: "Terminal", subtitle: "Running app", bundleIdentifier: "com.apple.Terminal")
        let terminus = LauncherCommand(title: "Terminus", subtitle: "Running app", bundleIdentifier: "com.example.Terminus")
        let usageStore = FixtureCommandUsageStore(usages: [
            terminus.usageIdentity: CommandUsage(
                selectionCount: 12,
                lastSelectedAt: Date(timeIntervalSinceNow: -60)
            )
        ])

        let results = FuzzyCommandMatcher(
            commands: [terminal, terminus],
            usageStore: usageStore
        ).search("term")

        #expect(results.first == terminus)
    }

    @Test("running app usage boosts installed app with same bundle identifier")
    func runningAppUsageBoostsInstalledRepresentation() {
        let runningTerminus = LauncherCommand(
            title: "Terminus",
            subtitle: "Running app",
            bundleIdentifier: "com.example.Terminus",
            resultType: .runningApplication,
            activationTarget: .runningApplication(
                bundleIdentifier: "com.example.Terminus",
                processIdentifier: 42
            )
        )
        let installedTerminus = LauncherCommand(
            title: "Terminus",
            subtitle: "Installed app",
            bundleIdentifier: "com.example.Terminus",
            activationTarget: .installedApplication(
                bundleIdentifier: "com.example.Terminus",
                applicationURL: URL(fileURLWithPath: "/Applications/Terminus.app")
            )
        )
        let terminal = LauncherCommand(title: "Terminal", subtitle: "Installed app", bundleIdentifier: "com.apple.Terminal")
        let usageStore = FixtureCommandUsageStore(usages: [
            runningTerminus.usageIdentity: CommandUsage(
                selectionCount: 12,
                lastSelectedAt: Date(timeIntervalSinceNow: -60)
            )
        ])

        let results = FuzzyCommandMatcher(
            commands: [terminal, installedTerminus],
            usageStore: usageStore
        ).search("term")

        #expect(results.first == installedTerminus)
    }

    @Test("strong text relevance prevents unrelated weak usage from dominating")
    func weakUsageDoesNotDominateStrongText() {
        let strong = LauncherCommand(title: "Team", subtitle: "Running app", bundleIdentifier: "com.example.Team")
        let weak = LauncherCommand(title: "Tiny Eventual Archive Monitor", subtitle: "Running app", bundleIdentifier: "com.example.TinyEventualArchiveMonitor")
        let usageStore = FixtureCommandUsageStore(usages: [
            weak.usageIdentity: CommandUsage(
                selectionCount: 500,
                lastSelectedAt: Date(timeIntervalSinceNow: -30)
            )
        ])

        let results = FuzzyCommandMatcher(
            commands: [weak, strong],
            usageStore: usageStore
        ).search("team")

        #expect(results.first == strong)
    }

    @Test("usage scoring combines frequency and recency")
    func usageScoringCombinesFrequencyAndRecency() {
        let now = Date()
        let frequentRecent = CommandUsage(selectionCount: 6, lastSelectedAt: now.addingTimeInterval(-60))
        let infrequentOld = CommandUsage(selectionCount: 1, lastSelectedAt: now.addingTimeInterval(-90 * 24 * 60 * 60))

        #expect(CommandUsageScorer.score(frequentRecent, now: now) > CommandUsageScorer.score(infrequentOld, now: now))
        #expect(CommandUsageScorer.score(nil, now: now) == 0)
    }
}

private final class FixtureCommandUsageStore: CommandUsageStoring {
    private let usages: [String: CommandUsage]

    init(usages: [String: CommandUsage]) {
        self.usages = usages
    }

    func usage(for identity: String) -> CommandUsage? {
        usages[identity]
    }

    func recordSelection(for identity: String, at date: Date) {}
}
