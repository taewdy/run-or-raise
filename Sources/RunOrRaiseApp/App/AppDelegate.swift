import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let commandProvider = CompositeCommandProvider(
            providers: [
                RunningWindowCommandProvider(),
                RunningApplicationCommandProvider(),
                InstalledApplicationCommandProvider(
                    cache: UserDefaultsInstalledApplicationCommandCache()
                )
            ]
        )
        let commandIndex = InMemoryCommandIndex(
            commands: commandProvider.commands(),
            provider: commandProvider,
            usageStore: UserDefaultsCommandUsageStore()
        )
        let permissionService = AccessibilityPermissionService()

        coordinator = AppCoordinator(
            commandIndex: commandIndex,
            permissionService: permissionService,
            hotKeyService: CarbonGlobalHotKeyService(),
            workspaceLauncher: NSWorkspaceLauncher()
        )
        coordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
