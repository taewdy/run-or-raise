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
    private let currentApplication: CurrentApplicationContext?

    init(
        commands: [LauncherCommand],
        usageStore: CommandUsageStoring = NoCommandUsageStore(),
        currentApplication: CurrentApplicationContext? = nil
    ) {
        self.commands = commands
        self.usageStore = usageStore
        self.currentApplication = currentApplication
    }

    func search(_ query: String) -> [LauncherCommand] {
        searchResults(query).map(\.command)
    }

    func searchResults(_ query: String) -> [CommandSearchResult] {
        let normalizedQuery = query.normalizedForSearch
        guard !normalizedQuery.isEmpty else {
            return emptyQueryResults()
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

    private func emptyQueryResults() -> [CommandSearchResult] {
        let now = Date()
        return commands
            .enumerated()
            .map { index, command in
                EmptyQueryCommand(
                    index: index,
                    command: command,
                    isCurrentApplication: command.matches(currentApplication),
                    usageScore: CommandUsageScorer.score(
                        usageStore.usage(for: command.usageIdentity),
                        now: now
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrentApplication != rhs.isCurrentApplication {
                    return !lhs.isCurrentApplication
                }
                if lhs.usageScore != rhs.usageScore {
                    return lhs.usageScore > rhs.usageScore
                }
                return lhs.index < rhs.index
            }
            .map { CommandSearchResult(command: $0.command, matchedRanges: []) }
    }

    private func bestMatch(for command: LauncherCommand, query: String) -> TextMatch? {
        let fieldMatches = command.searchFields
            .compactMap { field in
                match(field: field, query: query).map {
                    TextMatch(score: $0.score + field.weight, ranges: $0.ranges)
                }
            }

        let combinedMatches = command.combinedSearchFields.compactMap { combinedField in
            match(combinedField: combinedField, query: query).map {
                TextMatch(score: $0.score + combinedField.weight, ranges: $0.ranges)
            }
        }

        return (fieldMatches + combinedMatches)
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

    private func match(combinedField: CombinedSearchableCommandField, query: String) -> TextMatch? {
        let normalizedText = CombinedNormalizedSearchText(combinedField.fields)
        guard !normalizedText.characters.isEmpty else { return nil }

        if normalizedText.value == query {
            return TextMatch(
                score: 920 - normalizedText.characters.count,
                ranges: normalizedText.ranges(for: 0..<query.count)
            )
        }

        if normalizedText.value.hasPrefix(query) {
            return TextMatch(
                score: 770 - normalizedText.characters.count,
                ranges: normalizedText.ranges(for: 0..<query.count)
            )
        }

        if let range = normalizedText.value.range(of: query) {
            let start = normalizedText.value.distance(from: normalizedText.value.startIndex, to: range.lowerBound)
            let end = normalizedText.value.distance(from: normalizedText.value.startIndex, to: range.upperBound)
            let compactBonus = max(0, 120 - start)
            let boundaryBonus = normalizedText.isBoundary(at: start) ? 80 : 0
            return TextMatch(
                score: 540 + compactBonus + boundaryBonus - normalizedText.characters.count,
                ranges: normalizedText.ranges(for: start..<end)
            )
        }

        return fuzzyMatch(normalizedText: normalizedText, query: query)
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

    private func fuzzyMatch(
        normalizedText: CombinedNormalizedSearchText,
        query: String
    ) -> TextMatch? {
        var searchStart = 0
        var matchedOffsets: [Int] = []
        var score = 220
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

        guard score >= 140 else { return nil }

        return TextMatch(
            score: score,
            ranges: normalizedText.ranges(forOffsets: matchedOffsets)
        )
    }

    private func characterScore(
        at offset: Int,
        previousOffset: Int?,
        text: CombinedNormalizedSearchText
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

private struct EmptyQueryCommand {
    let index: Int
    let command: LauncherCommand
    let isCurrentApplication: Bool
    let usageScore: Double
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

private struct CombinedSearchableCommandField {
    let fields: [SearchableCommandField]
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

private struct CombinedNormalizedSearchText {
    let value: String
    let characters: [(character: Character, originalCharacter: Character, source: CombinedSearchSource?)]

    init(_ fields: [SearchableCommandField]) {
        var normalizedCharacters: [(character: Character, originalCharacter: Character, source: CombinedSearchSource?)] = []

        for field in fields where !field.value.isEmpty {
            if !normalizedCharacters.isEmpty {
                normalizedCharacters.append((" ", " ", nil))
            }

            for (offset, character) in field.value.enumerated() {
                let normalized = String(character)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                for normalizedCharacter in normalized {
                    normalizedCharacters.append((
                        normalizedCharacter,
                        character,
                        CombinedSearchSource(field: field.field, originalOffset: offset)
                    ))
                }
            }
        }

        self.characters = normalizedCharacters
        self.value = String(normalizedCharacters.map(\.character))
    }

    func firstOffset(of character: Character, startingAt start: Int) -> Int? {
        guard start < characters.count else { return nil }
        return characters[start...].firstIndex { $0.character == character }
    }

    func ranges(for normalizedOffsets: Range<Int>) -> [CommandMatchedRange] {
        let offsets = Array(normalizedOffsets)
        return ranges(forOffsets: offsets)
    }

    func ranges(forOffsets offsets: [Int]) -> [CommandMatchedRange] {
        let sources = offsets.compactMap { characters[safe: $0]?.source }
        guard !sources.isEmpty else { return [] }

        var ranges: [CommandMatchedRange] = []
        var rangeField = sources[0].field
        var rangeStart = sources[0].originalOffset
        var previous = sources[0].originalOffset

        for source in sources.dropFirst() {
            if source.field == rangeField, source.originalOffset == previous + 1 {
                previous = source.originalOffset
            } else {
                ranges.append(CommandMatchedRange(
                    field: rangeField,
                    location: rangeStart,
                    length: previous - rangeStart + 1
                ))
                rangeField = source.field
                rangeStart = source.originalOffset
                previous = source.originalOffset
            }
        }

        ranges.append(CommandMatchedRange(
            field: rangeField,
            location: rangeStart,
            length: previous - rangeStart + 1
        ))
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

private struct CombinedSearchSource: Equatable {
    let field: CommandSearchField
    let originalOffset: Int
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

    var combinedSearchFields: [CombinedSearchableCommandField] {
        let fields = searchFields
        guard fields.count > 1 else { return [] }

        return [
            CombinedSearchableCommandField(fields: fields, weight: -80),
            CombinedSearchableCommandField(fields: fields.reorderedForAppFirstMatching, weight: -80)
        ]
    }

    func matches(_ currentApplication: CurrentApplicationContext?) -> Bool {
        guard let currentApplication else { return false }

        if let currentBundleIdentifier = currentApplication.bundleIdentifier,
           bundleIdentifier == currentBundleIdentifier {
            return true
        }

        switch activationTarget {
        case .installedApplication(let bundleIdentifier, _):
            return bundleIdentifier == currentApplication.bundleIdentifier
        case .runningApplication(let bundleIdentifier, let processIdentifier),
                .runningWindow(let bundleIdentifier, let processIdentifier, _):
            if let currentBundleIdentifier = currentApplication.bundleIdentifier,
               bundleIdentifier == currentBundleIdentifier {
                return true
            }
            return currentApplication.processIdentifier == processIdentifier
        }
    }
}

private extension Array where Element == SearchableCommandField {
    var reorderedForAppFirstMatching: [SearchableCommandField] {
        sorted { lhs, rhs in
            appFirstPriority(lhs.field) < appFirstPriority(rhs.field)
        }
    }

    private func appFirstPriority(_ field: CommandSearchField) -> Int {
        switch field {
        case .subtitle:
            return 0
        case .title:
            return 1
        case .bundleIdentifier:
            return 2
        case .executableName:
            return 3
        case .path:
            return 4
        }
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
