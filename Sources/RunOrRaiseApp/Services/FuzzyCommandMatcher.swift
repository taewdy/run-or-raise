import Foundation

struct CommandSearchResult: Identifiable, Equatable {
    let command: LauncherCommand
    let matchedRanges: [CommandMatchedRange]

    var id: LauncherCommand.ID { command.id }
}

struct CommandMatchedRange: Equatable {
    let field: CommandSearchField
    let location: Int
    let length: Int
}

enum CommandSearchField: Equatable {
    case title
    case subtitle
    case bundleIdentifier
    case executableName
    case path
}

struct FuzzyCommandMatcher {
    private let commands: [LauncherCommand]
    private let usageStore: CommandUsageStoring

    init(commands: [LauncherCommand], usageStore: CommandUsageStoring = NoCommandUsageStore()) {
        self.commands = commands
        self.usageStore = usageStore
    }

    func search(_ query: String) -> [LauncherCommand] {
        searchResults(query).map(\.command)
    }

    func searchResults(_ query: String) -> [CommandSearchResult] {
        let normalizedQuery = query.normalizedForSearch
        guard !normalizedQuery.isEmpty else {
            return commands.map { CommandSearchResult(command: $0, matchedRanges: []) }
        }
        let now = Date()

        return commands
            .compactMap { command -> ScoredCommand? in
                guard let textMatch = bestMatch(for: command, query: normalizedQuery) else {
                    return nil
                }
                let usageScore = CommandUsageScorer.score(
                    usageStore.usage(for: command.usageIdentity),
                    now: now
                )
                return ScoredCommand(
                    command: command,
                    textScore: textMatch.score,
                    usageScore: usageScore,
                    matchedRanges: textMatch.ranges
                )
            }
            .sorted(by: ranksBefore)
            .map { CommandSearchResult(command: $0.command, matchedRanges: $0.matchedRanges) }
    }

    private func bestMatch(for command: LauncherCommand, query: String) -> TextMatch? {
        command.searchFields
            .compactMap { field in
                match(field: field, query: query).map {
                    TextMatch(score: $0.score + field.weight, ranges: $0.ranges)
                }
            }
            .max { lhs, rhs in lhs.score < rhs.score }
    }

    private func match(field: SearchableCommandField, query: String) -> TextMatch? {
        let normalizedText = NormalizedSearchText(field.value)
        guard !normalizedText.characters.isEmpty else { return nil }

        if normalizedText.value == query {
            return TextMatch(
                score: 1_000 - normalizedText.characters.count,
                ranges: [CommandMatchedRange(field: field.field, location: 0, length: field.value.count)]
            )
        }

        if normalizedText.value.hasPrefix(query), let ranges = normalizedText.ranges(for: 0..<query.count, field: field.field) {
            return TextMatch(score: 850 - normalizedText.characters.count, ranges: ranges)
        }

        if let range = normalizedText.value.range(of: query) {
            let start = normalizedText.value.distance(from: normalizedText.value.startIndex, to: range.lowerBound)
            let end = normalizedText.value.distance(from: normalizedText.value.startIndex, to: range.upperBound)
            let compactBonus = max(0, 120 - start)
            let boundaryBonus = normalizedText.isBoundary(at: start) ? 80 : 0
            return TextMatch(
                score: 620 + compactBonus + boundaryBonus - normalizedText.characters.count,
                ranges: normalizedText.ranges(for: start..<end, field: field.field) ?? []
            )
        }

        return fuzzyMatch(normalizedText: normalizedText, query: query, field: field.field)
    }

    private func fuzzyMatch(
        normalizedText: NormalizedSearchText,
        query: String,
        field: CommandSearchField
    ) -> TextMatch? {
        var searchStart = 0
        var matchedOffsets: [Int] = []
        var score = 300
        var previousOffset: Int?

        for character in query {
            guard let matchOffset = normalizedText.firstOffset(of: character, startingAt: searchStart) else {
                return nil
            }

            matchedOffsets.append(matchOffset)
            score += characterScore(
                at: matchOffset,
                previousOffset: previousOffset,
                text: normalizedText
            )
            previousOffset = matchOffset
            searchStart = matchOffset + 1
        }

        let span = (matchedOffsets.last ?? 0) - (matchedOffsets.first ?? 0) + 1
        score -= span * 6
        score -= normalizedText.characters.count

        guard score >= 180 else { return nil }

        return TextMatch(
            score: score,
            ranges: normalizedText.ranges(forOffsets: matchedOffsets, field: field)
        )
    }

    private func characterScore(
        at offset: Int,
        previousOffset: Int?,
        text: NormalizedSearchText
    ) -> Int {
        var score = 12

        if let previousOffset, previousOffset + 1 == offset {
            score += 60
        }

        if text.isBoundary(at: offset) {
            score += 48
        }

        if offset == 0 {
            score += 36
        }

        return score
    }

    private func ranksBefore(_ lhs: ScoredCommand, _ rhs: ScoredCommand) -> Bool {
        if lhs.combinedScore != rhs.combinedScore {
            return lhs.combinedScore > rhs.combinedScore
        }
        return lhs.command.title.localizedCaseInsensitiveCompare(rhs.command.title) == .orderedAscending
    }
}

private struct ScoredCommand {
    let command: LauncherCommand
    let textScore: Int
    let usageScore: Double
    let matchedRanges: [CommandMatchedRange]

    var combinedScore: Double {
        Double(textScore) + min(usageScore, usageBonusCap)
    }

    private var usageBonusCap: Double {
        if textScore >= 700 { return 220 }
        if textScore >= 500 { return 140 }
        if textScore >= 300 { return 60 }
        return 20
    }
}

private struct TextMatch {
    let score: Int
    let ranges: [CommandMatchedRange]
}

private struct SearchableCommandField {
    let field: CommandSearchField
    let value: String
    let weight: Int
}

private struct NormalizedSearchText {
    let value: String
    let characters: [(character: Character, originalCharacter: Character, originalOffset: Int)]

    init(_ text: String) {
        var normalizedCharacters: [(character: Character, originalCharacter: Character, originalOffset: Int)] = []

        for (offset, character) in text.enumerated() {
            let normalized = String(character)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            for normalizedCharacter in normalized {
                normalizedCharacters.append((normalizedCharacter, character, offset))
            }
        }

        self.characters = normalizedCharacters
        self.value = String(normalizedCharacters.map(\.character))
    }

    func firstOffset(of character: Character, startingAt start: Int) -> Int? {
        guard start < characters.count else { return nil }
        return characters[start...].firstIndex { $0.character == character }
    }

    func ranges(for normalizedOffsets: Range<Int>, field: CommandSearchField) -> [CommandMatchedRange]? {
        guard
            let lower = characters[safe: normalizedOffsets.lowerBound]?.originalOffset,
            let upper = characters[safe: normalizedOffsets.upperBound - 1]?.originalOffset
        else {
            return nil
        }

        return [CommandMatchedRange(field: field, location: lower, length: upper - lower + 1)]
    }

    func ranges(forOffsets offsets: [Int], field: CommandSearchField) -> [CommandMatchedRange] {
        let originalOffsets = offsets.compactMap { characters[safe: $0]?.originalOffset }
        guard !originalOffsets.isEmpty else { return [] }

        var ranges: [CommandMatchedRange] = []
        var rangeStart = originalOffsets[0]
        var previous = originalOffsets[0]

        for offset in originalOffsets.dropFirst() {
            if offset == previous + 1 {
                previous = offset
            } else {
                ranges.append(CommandMatchedRange(field: field, location: rangeStart, length: previous - rangeStart + 1))
                rangeStart = offset
                previous = offset
            }
        }

        ranges.append(CommandMatchedRange(field: field, location: rangeStart, length: previous - rangeStart + 1))
        return ranges
    }

    func isBoundary(at offset: Int) -> Bool {
        guard offset > 0, offset < characters.count else { return offset == 0 }

        let current = characters[offset].originalCharacter
        let previous = characters[offset - 1].originalCharacter

        if previous == "/" || previous == "." || previous == "-" || previous == "_" || previous == " " {
            return true
        }

        return previous.isLowercase && current.isUppercase
    }
}

private extension LauncherCommand {
    var searchFields: [SearchableCommandField] {
        [
            SearchableCommandField(field: .title, value: title, weight: 80),
            SearchableCommandField(field: .subtitle, value: subtitle, weight: 0),
            bundleIdentifier.map { SearchableCommandField(field: .bundleIdentifier, value: $0, weight: 30) },
            executableName.map { SearchableCommandField(field: .executableName, value: $0, weight: 50) },
            applicationPath.map { SearchableCommandField(field: .path, value: $0, weight: 20) }
        ].compactMap { $0 }
    }

    var applicationPath: String? {
        guard case .installedApplication(_, let applicationURL) = activationTarget else {
            return nil
        }
        return applicationURL?.standardizedFileURL.path
    }
}

extension LauncherCommand {
    var usageIdentity: String {
        switch activationTarget {
        case .installedApplication(let bundleIdentifier, let applicationURL):
            if let bundleIdentifier { return "app:bundle:\(bundleIdentifier)" }
            if let applicationURL { return "app:path:\(applicationURL.standardizedFileURL.path)" }
            return "app:title:\(title.normalizedForIdentity)"
        case .runningApplication(let bundleIdentifier, let processIdentifier):
            if let bundleIdentifier { return "app:bundle:\(bundleIdentifier)" }
            return "running:pid:\(processIdentifier)"
        case .runningWindow(let bundleIdentifier, let processIdentifier, let windowIdentifier):
            if let bundleIdentifier {
                return "window:bundle:\(bundleIdentifier):title:\(title.normalizedForIdentity)"
            }
            if let windowIdentifier {
                return "window:id:\(processIdentifier):\(windowIdentifier)"
            }
            return "window:pid:\(processIdentifier):title:\(title.normalizedForIdentity)"
        }
    }
}

extension String {
    var normalizedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedForIdentity: String {
        normalizedForSearch.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
