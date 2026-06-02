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
            viewModel?.selectNext()
        } else {
            show()
        }
    }

    func show() {
        let currentApplication = NSWorkspace.shared.frontmostApplication.map {
            CurrentApplicationContext(
                bundleIdentifier: $0.bundleIdentifier,
                processIdentifier: $0.processIdentifier
            )
        }
        let panel = window ?? makePanel()
        viewModel?.paletteOpened(currentApplication: currentApplication)
        center(panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        viewModel?.cancelRefresh()
        window?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let viewModel = CommandPaletteViewModel(
            commandIndex: commandIndex,
            launcher: workspaceLauncher,
            onCommandRun: { [weak self] in self?.hide() },
            onClose: { [weak self] in self?.hide() }
        )
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 330),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.paletteViewModel = viewModel
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
        guard let screenFrame = activeScreenFrame() else {
            panel.center()
            return
        }

        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activeScreenFrame() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }?.visibleFrame ?? NSScreen.main?.visibleFrame
    }
}

private final class CommandPalettePanel: NSPanel {
    weak var paletteViewModel: CommandPaletteViewModel?

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, handlePaletteKey(event) else {
            super.sendEvent(event)
            return
        }
    }

    private func handlePaletteKey(_ event: NSEvent) -> Bool {
        guard isVisible, let key = PaletteKey(event: event) else { return false }

        switch key {
        case .down:
            paletteViewModel?.selectNext()
        case .up:
            paletteViewModel?.selectPrevious()
        case .submit:
            Task { [weak paletteViewModel] in
                await paletteViewModel?.runSelectedCommand()
            }
        case .escape:
            paletteViewModel?.close()
        }
        return true
    }
}

enum PaletteKey: Equatable {
    case up
    case down
    case submit
    case escape

    init?(event: NSEvent) {
        self.init(keyCode: event.keyCode)
    }

    init?(keyCode: UInt16) {
        switch keyCode {
        case 53:
            self = .escape
        case 36, 76:
            self = .submit
        case 125:
            self = .down
        case 126:
            self = .up
        default:
            return nil
        }
    }
}
