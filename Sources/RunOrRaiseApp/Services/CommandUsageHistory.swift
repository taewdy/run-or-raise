import Foundation

struct CommandUsage: Codable, Equatable {
    let selectionCount: Int
    let lastSelectedAt: Date
}

protocol CommandUsageStoring: AnyObject {
    func usage(for identity: String) -> CommandUsage?
    func recordSelection(for identity: String, at date: Date)
}

final class NoCommandUsageStore: CommandUsageStoring {
    func usage(for identity: String) -> CommandUsage? {
        nil
    }

    func recordSelection(for identity: String, at date: Date) {}
}

final class UserDefaultsCommandUsageStore: CommandUsageStoring {
    private let userDefaults: UserDefaults
    private let key: String
    private var history: [String: CommandUsage]

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "CommandUsageHistory.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.history = Self.loadHistory(from: userDefaults, key: key)
    }

    func usage(for identity: String) -> CommandUsage? {
        history[identity]
    }

    func recordSelection(for identity: String, at date: Date = Date()) {
        let existing = history[identity]
        history[identity] = CommandUsage(
            selectionCount: (existing?.selectionCount ?? 0) + 1,
            lastSelectedAt: date
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        userDefaults.set(data, forKey: key)
    }

    private static func loadHistory(from userDefaults: UserDefaults, key: String) -> [String: CommandUsage] {
        guard
            let data = userDefaults.data(forKey: key),
            let history = try? JSONDecoder().decode([String: CommandUsage].self, from: data)
        else {
            return [:]
        }
        return history
    }
}

enum CommandUsageScorer {
    static func score(_ usage: CommandUsage?, now: Date) -> Double {
        guard let usage else { return 0 }

        let frequency = log(Double(usage.selectionCount) + 1) * 80
        let age = max(0, now.timeIntervalSince(usage.lastSelectedAt))
        let recency = 120 * exp(-age / (14 * 24 * 60 * 60))

        return frequency + recency
    }
}
