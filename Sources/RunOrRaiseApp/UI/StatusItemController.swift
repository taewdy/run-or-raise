import AppKit

@MainActor
final class StatusItemController: NSObject, StatusItemControlling {
    private let statusItem: NSStatusItem
    private let permissionService: PermissionStatusProviding
    private let commandIndex: CommandIndex
    private let hotKey: HotKeyDescriptor
    private var hotKeyError: String?

    private var onOpenPalette: (() -> Void)?
    private var onReindex: (() -> Void)?
    private var onRequestPermissions: (() -> Void)?
    private var onQuit: (() -> Void)?

    init(
        permissionService: PermissionStatusProviding,
        commandIndex: CommandIndex,
        hotKey: HotKeyDescriptor,
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    ) {
        self.permissionService = permissionService
        self.commandIndex = commandIndex
        self.hotKey = hotKey
        self.statusItem = statusItem
        super.init()
    }

    func configure(
        onOpenPalette: @escaping () -> Void,
        onReindex: @escaping () -> Void,
        onRequestPermissions: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenPalette = onOpenPalette
        self.onReindex = onReindex
        self.onRequestPermissions = onRequestPermissions
        self.onQuit = onQuit

        statusItem.button?.title = "Run"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusButtonClicked)
        rebuildMenu()
    }

    func refresh() {
        rebuildMenu()
    }

    func setHotKeyError(_ message: String) {
        hotKeyError = message
        rebuildMenu()
    }

    @objc private func statusButtonClicked() {
        onOpenPalette?()
    }

    @objc private func openPalette() {
        onOpenPalette?()
    }

    @objc private func reindex() {
        onReindex?()
    }

    @objc private func requestPermissions() {
        onRequestPermissions?()
    }

    @objc private func quit() {
        onQuit?()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(actionItem("Open Palette", action: #selector(openPalette), keyEquivalent: " "))
        menu.addItem(disabledItem("Hotkey: \(hotKey.displayText)"))

        if let hotKeyError {
            menu.addItem(disabledItem("Hotkey unavailable: \(hotKeyError)"))
        }

        menu.addItem(.separator())
        addPermissionItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(disabledItem("Indexed commands: \(commandIndex.allCommands.count)"))
        menu.addItem(actionItem("Reindex", action: #selector(reindex)))
        menu.addItem(disabledItem("Settings: not needed for local v1"))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit RunOrRaise", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func addPermissionItems(to menu: NSMenu) {
        for status in permissionService.currentStatuses() {
            let suffix = status.isGranted ? "Granted" : "Missing - window focus disabled"
            menu.addItem(disabledItem("\(status.name): \(suffix)"))
            if !status.isGranted {
                menu.addItem(actionItem(status.recoveryAction, action: #selector(requestPermissions)))
            }
        }
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
