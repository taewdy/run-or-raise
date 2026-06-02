import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @StateObject private var viewModel: CommandPaletteViewModel
    @FocusState private var isSearchFocused: Bool

    init(viewModel: CommandPaletteViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Run or raise...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .focused($isSearchFocused)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .onSubmit {
                    Task { await viewModel.runSelectedCommand() }
                }

            if let launchMessage = viewModel.launchMessage {
                Text(launchMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }

            Divider()

            ZStack {
                if viewModel.shouldShowResults {
                    ScrollViewReader { proxy in
                        List(selection: $viewModel.selectedCommandID) {
                            ForEach(viewModel.resultItems) { item in
                                CommandRow(item: item)
                                    .id(item.id)
                                    .tag(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedCommandID = item.id
                                        Task { await viewModel.runSelectedCommand() }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .onChange(of: viewModel.resultsRevision) { _, _ in
                            guard let selectedCommandID = viewModel.selectedCommandID else { return }
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.08)) {
                                    proxy.scrollTo(selectedCommandID, anchor: .top)
                                }
                            }
                        }
                    }
                } else if viewModel.shouldShowLoadingState {
                    PaletteStateLabel(text: "Refreshing apps and windows...")
                } else if viewModel.shouldShowEmptyState {
                    PaletteStateLabel(text: viewModel.emptyStateText)
                }

                if viewModel.shouldShowRefreshIndicator {
                    RefreshIndicator()
                        .padding(10)
                }
            }
            .frame(height: 260)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 24, y: 12)
        .onAppear {
            isSearchFocused = true
        }
    }
}

private struct CommandRow: View {
    let item: CommandPaletteResultItem

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(activationTarget: item.activationTarget)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(item.title, field: .title, fontSize: 15))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(highlighted(item.subtitle, field: .subtitle, fontSize: 12))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(item.targetDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(item.badgeText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(badgeForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(badgeBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
    }

    private var badgeForeground: Color {
        switch item.resultType {
        case .installedApplication:
            return .blue
        case .runningApplication:
            return .green
        case .runningWindow:
            return .orange
        }
    }

    private var badgeBackground: Color {
        badgeForeground.opacity(0.12)
    }

    private func highlighted(_ text: String, field: CommandSearchField, fontSize: CGFloat) -> AttributedString {
        var attributed = AttributedString(text)
        for matchedRange in item.matchedRanges where matchedRange.field == field {
            guard let range = attributed.range(for: matchedRange, in: text) else { continue }
            attributed[range].foregroundColor = .accentColor
            attributed[range].font = .system(size: fontSize, weight: .bold)
        }
        return attributed
    }
}

private struct AppIconView: View {
    let activationTarget: CommandActivationTarget

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var icon: NSImage {
        switch activationTarget {
        case .installedApplication(_, let applicationURL):
            if let applicationURL {
                return NSWorkspace.shared.icon(forFile: applicationURL.path)
            }
        case .runningApplication(let bundleIdentifier, let processIdentifier),
                .runningWindow(let bundleIdentifier, let processIdentifier, _):
            if let bundleURL = NSRunningApplication(processIdentifier: processIdentifier)?.bundleURL {
                return NSWorkspace.shared.icon(forFile: bundleURL.path)
            }
            if let bundleIdentifier,
               let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return NSWorkspace.shared.icon(forFile: applicationURL.path)
            }
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct PaletteStateLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RefreshIndicator: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .padding(5)
                    .background(.regularMaterial, in: Circle())
            }
            Spacer()
        }
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
