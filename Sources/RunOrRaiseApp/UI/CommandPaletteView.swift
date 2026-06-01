import SwiftUI

struct CommandPaletteView: View {
    @StateObject private var viewModel: CommandPaletteViewModel

    init(viewModel: CommandPaletteViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Run or raise...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .onSubmit(viewModel.runSelectedCommand)

            Divider()

            List(selection: $viewModel.selectedCommandID) {
                ForEach(viewModel.results) { result in
                    CommandRow(result: result)
                        .tag(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedCommandID = result.id
                            viewModel.runSelectedCommand()
                        }
                }
            }
            .listStyle(.plain)
            .frame(height: 260)
        }
        .frame(width: 560)
        .background(.regularMaterial)
    }
}

private struct CommandRow: View {
    let result: CommandSearchResult

    private var command: LauncherCommand { result.command }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(highlighted(command.title, field: .title))
                .font(.system(size: 15, weight: .semibold))
            Text(highlighted(command.subtitle, field: .subtitle))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func highlighted(_ text: String, field: CommandSearchField) -> AttributedString {
        var attributed = AttributedString(text)
        for matchedRange in result.matchedRanges where matchedRange.field == field {
            guard let range = attributed.range(for: matchedRange, in: text) else { continue }
            attributed[range].foregroundColor = .accentColor
            attributed[range].font = .system(size: field == .title ? 15 : 12, weight: .bold)
        }
        return attributed
    }
}

private extension AttributedString {
    func range(for matchedRange: CommandMatchedRange, in text: String) -> Range<AttributedString.Index>? {
        guard
            let lower = index(startIndex, offsetByCharacters: matchedRange.location),
            let upper = index(lower, offsetByCharacters: matchedRange.length)
        else {
            return nil
        }
        return lower..<upper
    }

    func index(_ index: AttributedString.Index, offsetByCharacters offset: Int) -> AttributedString.Index? {
        var current = index
        for _ in 0..<offset {
            guard current < endIndex else { return nil }
            current = characters.index(after: current)
        }
        return current
    }
}
