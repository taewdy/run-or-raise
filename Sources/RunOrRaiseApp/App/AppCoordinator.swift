import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let commandIndex: CommandIndex
    private let permissionService: PermissionStatusProviding
    private let hotKeyService: GlobalHotKeyRegistering
    private let workspaceLauncher: WorkspaceLaunching
    private let paletteController: CommandPaletteWindowControlling
    private let statusItemController: StatusItemControlling
    private let hotKey: HotKeyDescriptor

    init(
        commandIndex: CommandIndex,
        permissionService: PermissionStatusProviding,
        hotKeyService: GlobalHotKeyRegistering,
        workspaceLauncher: WorkspaceLaunching,
        hotKey: HotKeyDescriptor = .default,
        paletteController: CommandPaletteWindowControlling? = nil,
        statusItemController: StatusItemControlling? = nil
    ) {
        self.commandIndex = commandIndex
        self.permissionService = permissionService
        self.hotKeyService = hotKeyService
        self.workspaceLauncher = workspaceLauncher
        self.hotKey = hotKey
        self.paletteController = paletteController ?? CommandPaletteWindowController(
            commandIndex: commandIndex,
            workspaceLauncher: workspaceLauncher
        )
        self.statusItemController = statusItemController ?? StatusItemController(
            permissionService: permissionService,
            commandIndex: commandIndex,
            hotKey: hotKey
        )
    }

    func start() {
        statusItemController.configure(
            onOpenPalette: { [weak self] in self?.togglePalette() },
            onReindex: { [weak self] in self?.reindex() },
            onRequestPermissions: { [weak self] in self?.requestPermissions() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        do {
            try hotKeyService.register(hotKey) { [weak self] in
                self?.togglePalette()
            }
        } catch {
            statusItemController.setHotKeyError(error.localizedDescription)
        }
    }

    func stop() {
        hotKeyService.unregister()
    }

    private func togglePalette() {
        paletteController.toggle()
    }

    private func reindex() {
        commandIndex.reindex()
        statusItemController.refresh()
    }

    private func requestPermissions() {
        _ = permissionService.requestPermission()
        statusItemController.refresh()
    }
}

@MainActor
protocol StatusItemControlling {
    func configure(
        onOpenPalette: @escaping () -> Void,
        onReindex: @escaping () -> Void,
        onRequestPermissions: @escaping () -> Void,
        onQuit: @escaping () -> Void
    )
    func refresh()
    func setHotKeyError(_ message: String)
}

@MainActor
protocol CommandPaletteWindowControlling {
    func toggle()
}
