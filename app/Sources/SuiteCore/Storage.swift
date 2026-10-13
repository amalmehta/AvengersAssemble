import Foundation
import Security

// MARK: - Data folder

public enum SuitePaths {
    /// `SUITE_HOME`, or ~/Library/Application Support/Suite of Agents/.
    public static func dataFolder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = environment["SUITE_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Suite of Agents", isDirectory: true)
    }

    public static func runFolder(dataFolder: URL, runId: String) -> URL {
        dataFolder.appendingPathComponent("runs", isDirectory: true).appendingPathComponent(runId, isDirectory: true)
    }

    /// Resolves a task's `output_path` (relative to `runs/<run_id>/`) to a file URL.
    public static func outputURL(outputPath: String, runFolder: URL) -> URL {
        if outputPath.hasPrefix("/") { return URL(fileURLWithPath: outputPath) }
        return runFolder.appendingPathComponent(outputPath)
    }
}

// MARK: - settings.json

/// The engine-facing preferences stored in `<data folder>/settings.json`.
public struct EngineSettings: Equatable, Sendable {
    public var mock: Bool = true
    public var maxCostUsd: Double = 2.0
    public var maxTasks: Int = 40
    public var userRatingWeight: Double = 3.0
    public var costPenaltyPerUsd: Double = 0.2
    public var maxAgentSteps: Int = 10
    public var maxParallelTasks: Int = 3

    public init() {}

    public init(json o: [String: Any]) {
        if let v = o["mock"] as? Bool { mock = v }
        if let v = (o["max_cost_usd"] as? NSNumber)?.doubleValue { maxCostUsd = v }
        if let v = (o["max_tasks"] as? NSNumber)?.intValue { maxTasks = v }
        if let v = (o["user_rating_weight"] as? NSNumber)?.doubleValue { userRatingWeight = v }
        if let v = (o["cost_penalty_per_usd"] as? NSNumber)?.doubleValue { costPenaltyPerUsd = v }
        if let v = (o["max_agent_steps"] as? NSNumber)?.intValue { maxAgentSteps = v }
        if let v = (o["max_parallel_tasks"] as? NSNumber)?.intValue { maxParallelTasks = v }
    }

    public var json: [String: Any] {
        ["mock": mock, "max_cost_usd": maxCostUsd, "max_tasks": maxTasks,
         "user_rating_weight": userRatingWeight, "cost_penalty_per_usd": costPenaltyPerUsd,
         "max_agent_steps": maxAgentSteps, "max_parallel_tasks": maxParallelTasks]
    }
}

public enum SettingsFile {
    public static func url(in dataFolder: URL) -> URL { dataFolder.appendingPathComponent("settings.json") }

    public static func readRaw(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return obj
    }

    public static func load(from url: URL) -> EngineSettings { EngineSettings(json: readRaw(from: url)) }

    /// Our keys win; any key we don't know about is kept as-is.
    public static func merged(existing: [String: Any], with settings: EngineSettings) -> [String: Any] {
        var out = existing
        for (k, v) in settings.json { out[k] = v }
        return out
    }

    public static func save(_ settings: EngineSettings, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let merged = merged(existing: readRaw(from: url), with: settings)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Feedback

public enum FeedbackLog {
    public static func append(text: String, appVersion: String, dataFolder: URL, date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        let url = dataFolder.appendingPathComponent("feedback.jsonl")
        let f = ISO8601DateFormatter()
        let entry: [String: Any] = ["date": f.string(from: date), "text": text, "app_version": appVersion]
        var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Keychain

public enum Keychain {
    public static let service = "Suite of Agents"
    public static let apiKeyAccount = "ANTHROPIC_API_KEY"

    public static func read(account: String = apiKeyAccount) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    @discardableResult
    public static func save(_ value: String, account: String = apiKeyAccount) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Suite of Agents — Anthropic API key"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    public static func delete(account: String = apiKeyAccount) -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let s = SecItemDelete(q as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }
}
