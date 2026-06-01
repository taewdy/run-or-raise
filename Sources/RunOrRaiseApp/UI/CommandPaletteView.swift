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
                ForEach(viewModel.results) { command in
                    CommandRow(command: command)
                        .tag(command.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedCommandID = command.id
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
    let command: LauncherCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(command.title)
                .font(.system(size: 15, weight: .semibold))
            Text(command.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
