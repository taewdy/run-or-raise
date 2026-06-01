import AppKit
import SwiftUI

@MainActor
final class CommandPaletteWindowController: CommandPaletteWindowControlling {
    private let commandIndex: CommandIndex
    private let workspaceLauncher: WorkspaceLaunching
    private var window: NSPanel?
    private var viewModel: CommandPaletteViewModel?

    init(commandIndex: CommandIndex, workspaceLauncher: WorkspaceLaunching) {
        self.commandIndex = commandIndex
        self.workspaceLauncher = workspaceLauncher
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        let panel = window ?? makePanel()
        viewModel?.reset()
        center(panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: workspaceLauncher,
            onCommandRun: { [weak self] in self?.hide() }
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 330),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CommandPaletteView(viewModel: viewModel))

        self.viewModel = viewModel
        self.window = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }

        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - panel.frame.height - 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
