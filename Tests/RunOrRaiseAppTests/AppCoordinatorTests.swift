import Foundation
import Testing
@testable import RunOrRaiseApp

@MainActor
@Suite("App coordinator")
struct AppCoordinatorTests {
    @Test("start shows palette so opening the app has visible feedback")
    func startShowsPalette() {
        let palette = RecordingPaletteController()
        let coordinator = AppCoordinator(
            commandIndex: InMemoryCommandIndex(commands: []),
            permissionService: StaticPermissionService(),
            hotKeyService: RecordingHotKeyService(),
            workspaceLauncher: RecordingCoordinatorWorkspaceLauncher(),
            paletteController: palette,
            statusItemController: RecordingStatusItemController()
        )

        coordinator.start()

        #expect(palette.showCount == 1)
        #expect(palette.toggleCount == 0)
    }

    @Test("present palette shows without toggling an already visible palette closed")
    func presentPaletteShowsWithoutToggling() {
        let palette = RecordingPaletteController()
        let coordinator = AppCoordinator(
            commandIndex: InMemoryCommandIndex(commands: []),
            permissionService: StaticPermissionService(),
            hotKeyService: RecordingHotKeyService(),
            workspaceLauncher: RecordingCoordinatorWorkspaceLauncher(),
            showPaletteOnLaunch: false,
            paletteController: palette,
            statusItemController: RecordingStatusItemController()
        )

        coordinator.start()
        coordinator.presentPalette()
        coordinator.presentPalette()

        #expect(palette.showCount == 2)
        #expect(palette.toggleCount == 0)
    }

    @Test("start requests missing accessibility permission before indexing window titles")
    func startRequestsMissingAccessibilityPermission() {
        let permissionService = RecordingPermissionService(
            statuses: [
                PermissionStatus(
                    name: "Accessibility",
                    isGranted: false,
                    recoveryAction: "Open Accessibility Settings"
                )
            ]
        )
        let coordinator = AppCoordinator(
            commandIndex: InMemoryCommandIndex(commands: []),
            permissionService: permissionService,
            hotKeyService: RecordingHotKeyService(),
            workspaceLauncher: RecordingCoordinatorWorkspaceLauncher(),
            showPaletteOnLaunch: false,
            paletteController: RecordingPaletteController(),
            statusItemController: RecordingStatusItemController()
        )

        coordinator.start()

        #expect(permissionService.requestPermissionCount == 1)
    }
}

@MainActor
private final class RecordingPaletteController: CommandPaletteWindowControlling {
    private(set) var showCount = 0
    private(set) var toggleCount = 0

    func show() {
        showCount += 1
    }

    func toggle() {
        toggleCount += 1
    }
}

@MainActor
private final class RecordingStatusItemController: StatusItemControlling {
    private(set) var didConfigure = false
    private(set) var hotKeyError: String?

    func configure(
        onOpenPalette: @escaping () -> Void,
        onReindex: @escaping () -> Void,
        onRequestPermissions: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        didConfigure = true
    }

    func refresh() {}

    func setHotKeyError(_ message: String) {
        hotKeyError = message
    }
}

@MainActor
private final class RecordingHotKeyService: GlobalHotKeyRegistering {
    private(set) var registeredHotKey: HotKeyDescriptor?

    func register(_ hotKey: HotKeyDescriptor, action: @escaping () -> Void) throws {
        registeredHotKey = hotKey
    }

    func unregister() {}
}

@MainActor
private struct StaticPermissionService: PermissionStatusProviding {
    func currentStatuses() -> [PermissionStatus] { [] }
    func requestPermission() -> Bool { true }
}

@MainActor
private final class RecordingPermissionService: PermissionStatusProviding {
    private let statuses: [PermissionStatus]
    private(set) var requestPermissionCount = 0

    init(statuses: [PermissionStatus]) {
        self.statuses = statuses
    }

    func currentStatuses() -> [PermissionStatus] {
        statuses
    }

    func requestPermission() -> Bool {
        requestPermissionCount += 1
        return false
    }
}

@MainActor
private struct RecordingCoordinatorWorkspaceLauncher: WorkspaceLaunching {
    func openOrRaise(_ command: LauncherCommand) async -> WorkspaceLaunchResult {
        .targetUnavailable
    }
}
