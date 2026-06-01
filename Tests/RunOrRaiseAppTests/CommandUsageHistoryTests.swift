import Foundation
import Testing
@testable import RunOrRaiseApp

@Suite("Command usage history")
struct CommandUsageHistoryTests {
    @Test("user defaults store persists selection counts by identity")
    func userDefaultsStorePersistsSelections() throws {
        let suiteName = "RunOrRaiseAppTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let firstStore = UserDefaultsCommandUsageStore(userDefaults: userDefaults, key: "usage")
        let selectedAt = Date()

        firstStore.recordSelection(for: "app:bundle:com.example.App", at: selectedAt)
        firstStore.recordSelection(for: "app:bundle:com.example.App", at: selectedAt.addingTimeInterval(10))

        let secondStore = UserDefaultsCommandUsageStore(userDefaults: userDefaults, key: "usage")

        #expect(secondStore.usage(for: "app:bundle:com.example.App") == CommandUsage(
            selectionCount: 2,
            lastSelectedAt: selectedAt.addingTimeInterval(10)
        ))
    }

    @Test("window usage identity is stable across window identifiers when bundle and title match")
    func windowUsageIdentityUsesBundleAndTitle() {
        let firstWindow = LauncherCommand(
            title: "Inbox",
            subtitle: "Window in Mail",
            bundleIdentifier: "com.apple.mail",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 100,
                windowIdentifier: 1
            )
        )
        let secondWindow = LauncherCommand(
            title: "Inbox",
            subtitle: "Window in Mail",
            bundleIdentifier: "com.apple.mail",
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 200,
                windowIdentifier: 2
            )
        )

        #expect(firstWindow.usageIdentity == secondWindow.usageIdentity)
    }
}
