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

struct RunningAccessibilityWindowSnapshot: Equatable {
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

        return snapshots(from: windowInfo, accessibilityWindows: accessibilityWindowSnapshots)
    }

    static func snapshots(
        from windowInfo: [[String: Any]],
        accessibilityWindows: (pid_t) -> [RunningAccessibilityWindowSnapshot]
    ) -> [RunningWindowSnapshot] {
        var accessibilityCache: [pid_t: [CGWindowID: String]] = [:]

        return windowInfo.compactMap { info in
            makeSnapshot(from: info) { processIdentifier, windowIdentifier in
                guard let windowIdentifier else { return nil }
                if accessibilityCache[processIdentifier] == nil {
                    accessibilityCache[processIdentifier] = Dictionary(
                        uniqueKeysWithValues: accessibilityWindows(processIdentifier).compactMap { snapshot in
                            guard let identifier = snapshot.windowIdentifier else { return nil }
                            return (identifier, snapshot.title)
                        }
                    )
                }
                return accessibilityCache[processIdentifier]?[windowIdentifier]
            }
        }
    }

    private static func makeSnapshot(
        from info: [String: Any],
        accessibilityTitle: (pid_t, CGWindowID?) -> String? = { _, _ in nil }
    ) -> RunningWindowSnapshot? {
        guard
            let processIdentifier = pid(from: info[kCGWindowOwnerPID as String]),
            let layer = int(from: info[kCGWindowLayer as String]),
            layer == 0
        else {
            return nil
        }

        let windowIdentifier = int(from: info[kCGWindowNumber as String]).map(CGWindowID.init)
        let title = title(
            from: info[kCGWindowName as String] as? String,
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier,
            accessibilityTitle: accessibilityTitle
        )
        guard !title.isEmpty else { return nil }

        let runningApplication = NSRunningApplication(processIdentifier: processIdentifier)
        let ownerName = (info[kCGWindowOwnerName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = runningApplication?.localizedName ?? ownerName
        guard let appName, !appName.isEmpty else { return nil }

        return RunningWindowSnapshot(
            appName: appName,
            bundleIdentifier: runningApplication?.bundleIdentifier,
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier,
            title: title
        )
    }

    private static func title(
        from coreGraphicsTitle: String?,
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID?,
        accessibilityTitle: (pid_t, CGWindowID?) -> String?
    ) -> String {
        let title = coreGraphicsTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            return title
        }
        return accessibilityTitle(processIdentifier, windowIdentifier)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func accessibilityWindowSnapshots(processIdentifier: pid_t) -> [RunningAccessibilityWindowSnapshot] {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )
        guard result == .success, let windows = rawWindows as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            guard let title = axTitle(window), !title.isEmpty else { return nil }
            return RunningAccessibilityWindowSnapshot(
                windowIdentifier: axWindowIdentifier(window),
                title: title
            )
        }
    }

    private static func axTitle(_ window: AXUIElement) -> String? {
        var rawTitle: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &rawTitle
        )
        guard result == .success else { return nil }
        return rawTitle as? String
    }

    private static func axWindowIdentifier(_ window: AXUIElement) -> CGWindowID? {
        var rawIdentifier: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            "AXWindowNumber" as CFString,
            &rawIdentifier
        )
        guard result == .success else { return nil }

        if let identifier = rawIdentifier as? CGWindowID {
            return identifier
        }
        if let identifier = rawIdentifier as? Int {
            return CGWindowID(identifier)
        }
        if let identifier = rawIdentifier as? NSNumber {
            return CGWindowID(identifier.uint32Value)
        }
        return nil
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
