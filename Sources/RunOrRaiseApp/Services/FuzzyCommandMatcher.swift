import Foundation

struct FuzzyCommandMatcher {
    private let commands: [LauncherCommand]

    init(commands: [LauncherCommand]) {
        self.commands = commands
    }

    func search(_ query: String) -> [LauncherCommand] {
        let normalizedQuery = query.normalizedForSearch
        guard !normalizedQuery.isEmpty else { return commands }

        return commands
            .compactMap { command -> ScoredCommand? in
                let score = score(command: command, query: normalizedQuery)
                return score.map { ScoredCommand(command: command, score: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.command.title.localizedCaseInsensitiveCompare(rhs.command.title) == .orderedAscending
            }
            .map(\.command)
    }

    private func score(command: LauncherCommand, query: String) -> Int? {
        let title = command.title.normalizedForSearch
        let subtitle = command.subtitle.normalizedForSearch

        if title == query { return 1000 }
        if title.hasPrefix(query) { return 800 - title.count }
        if title.contains(query) { return 600 - title.distance(to: query) }
        if let fuzzyScore = fuzzyScore(text: title, query: query) {
            return 400 + fuzzyScore
        }
        if subtitle.contains(query) { return 150 }
        return nil
    }

    private func fuzzyScore(text: String, query: String) -> Int? {
        var searchStart = text.startIndex
        var score = 0
        var previousMatch: String.Index?

        for character in query {
            guard let match = text[searchStart...].firstIndex(of: character) else {
                return nil
            }
            if let previousMatch, text.index(after: previousMatch) == match {
                score += 8
            } else {
                score += 2
            }
            if match == text.startIndex {
                score += 4
            }
            previousMatch = match
            searchStart = text.index(after: match)
        }

        return score - text.count
    }
}

private struct ScoredCommand {
    let command: LauncherCommand
    let score: Int
}

private extension String {
    var normalizedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func distance(to query: String) -> Int {
        guard let range = range(of: query) else { return count }
        return distance(from: startIndex, to: range.lowerBound)
    }
}
