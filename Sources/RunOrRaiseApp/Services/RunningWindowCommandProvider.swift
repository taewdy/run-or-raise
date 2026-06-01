import AppKit
import CoreGraphics
import Foundation

struct RunningWindowSnapshot: Equatable {
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowIdentifier: CGWindowID?
    let title: String
}

final class RunningWindowCommandProvider: CommandProviding {
    private let snapshots: () -> [RunningWindowSnapshot]

    init(snapshots: @escaping () -> [RunningWindowSnapshot] = RunningWindowCommandProvider.currentSnapshots) {
        self.snapshots = snapshots
    }

    func commands() -> [LauncherCommand] {
        snapshots()
            .map(makeCommand)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    static func currentSnapshots() -> [RunningWindowSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap(makeSnapshot)
    }

    private static func makeSnapshot(from info: [String: Any]) -> RunningWindowSnapshot? {
        guard
            let processIdentifier = pid(from: info[kCGWindowOwnerPID as String]),
            let layer = int(from: info[kCGWindowLayer as String]),
            layer == 0,
            let rawTitle = info[kCGWindowName as String] as? String
        else {
            return nil
        }

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let runningApplication = NSRunningApplication(processIdentifier: processIdentifier)
        let ownerName = (info[kCGWindowOwnerName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = runningApplication?.localizedName ?? ownerName
        guard let appName, !appName.isEmpty else { return nil }

        let windowIdentifier = int(from: info[kCGWindowNumber as String]).map(CGWindowID.init)

        return RunningWindowSnapshot(
            appName: appName,
            bundleIdentifier: runningApplication?.bundleIdentifier,
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier,
            title: title
        )
    }

    private static func pid(from value: Any?) -> pid_t? {
        int(from: value).map(pid_t.init)
    }

    private static func int(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int32 {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func makeCommand(_ snapshot: RunningWindowSnapshot) -> LauncherCommand {
        LauncherCommand(
            title: snapshot.title,
            subtitle: "Window in \(snapshot.appName)",
            bundleIdentifier: snapshot.bundleIdentifier,
            resultType: .runningWindow,
            activationTarget: .runningWindow(
                bundleIdentifier: snapshot.bundleIdentifier,
                processIdentifier: snapshot.processIdentifier,
                windowIdentifier: snapshot.windowIdentifier
            )
        )
    }
}
