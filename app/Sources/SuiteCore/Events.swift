import Foundation

/// One event from `suite run --json` (one JSON object per line).
public enum RunEvent: Sendable, Equatable {
    case runStarted(runId: String, goal: String, mock: Bool, maxCostUsd: Double?, maxTasks: Int?)
    case plan(round: Int, tasks: [SuiteTask])
    case taskAssigned(taskId: String, kind: String?, agent: String, variant: String, samples: [String: Double])
    case toolCall(taskId: String, tool: String, summary: String)
    case agentText(taskId: String, text: String)
    case taskFinished(taskId: String, status: TaskStatus, summary: String?, outputPath: String?, costUsd: Double?)
    case taskScored(taskId: String, score: Double, rationale: String?)
    case budget(spentUsd: Double, maxCostUsd: Double?, tasksDone: Int, maxTasks: Int?)
    case runFinished(runId: String?, status: String, reportPath: String?, spentUsd: Double?)
    case error(message: String)
    /// A JSON object with a `type` we don't know. Ignored, kept for forward compatibility.
    case unknown(type: String)
    /// A line that wasn't a JSON object (e.g. a stray print). Ignored.
    case unparsed(line: String)
}

public enum RunEventDecoder {
    /// Decodes one line. Returns nil for blank lines.
    public static func decode(line raw: String) -> RunEvent? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard line.first == "{", let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unparsed(line: line)
        }
        return decode(object: obj)
    }

    public static func decode(object o: [String: Any]) -> RunEvent {
        let type = str(o["type"]) ?? ""
        switch type {
        case "run_started":
            return .runStarted(runId: str(o["run_id"]) ?? "", goal: str(o["goal"]) ?? "",
                               mock: bool(o["mock"]) ?? false,
                               maxCostUsd: dbl(o["max_cost_usd"]), maxTasks: int(o["max_tasks"]))
        case "plan":
            var tasks: [SuiteTask] = []
            if let arr = o["tasks"] as? [Any] {
                for item in arr {
                    guard let d = try? JSONSerialization.data(withJSONObject: item),
                          let t = try? JSONDecoder().decode(SuiteTask.self, from: d) else { continue }
                    tasks.append(t)
                }
            }
            return .plan(round: int(o["round"]) ?? 1, tasks: tasks)
        case "task_assigned":
            var samples: [String: Double] = [:]
            if let s = o["samples"] as? [String: Any] {
                for (k, v) in s { if let d = dbl(v) { samples[k] = d } }
            }
            return .taskAssigned(taskId: str(o["task_id"]) ?? "", kind: str(o["kind"]),
                                 agent: str(o["agent"]) ?? "", variant: str(o["variant"]) ?? "",
                                 samples: samples)
        case "tool_call":
            return .toolCall(taskId: str(o["task_id"]) ?? "", tool: str(o["tool"]) ?? "tool",
                             summary: str(o["summary"]) ?? "")
        case "agent_text":
            return .agentText(taskId: str(o["task_id"]) ?? "", text: str(o["text"]) ?? "")
        case "task_finished":
            return .taskFinished(taskId: str(o["task_id"]) ?? "", status: TaskStatus(lenient: str(o["status"]) ?? "done"),
                                 summary: str(o["summary"]), outputPath: str(o["output_path"]),
                                 costUsd: dbl(o["cost_usd"]))
        case "task_scored":
            return .taskScored(taskId: str(o["task_id"]) ?? "", score: dbl(o["score"]) ?? 0,
                               rationale: str(o["rationale"]))
        case "budget":
            return .budget(spentUsd: dbl(o["spent_usd"]) ?? 0, maxCostUsd: dbl(o["max_cost_usd"]),
                           tasksDone: int(o["tasks_done"]) ?? 0, maxTasks: int(o["max_tasks"]))
        case "run_finished":
            return .runFinished(runId: str(o["run_id"]), status: str(o["status"]) ?? "done",
                                reportPath: str(o["report_path"]), spentUsd: dbl(o["spent_usd"]))
        case "error":
            return .error(message: str(o["message"]) ?? "Unknown engine error")
        default:
            return .unknown(type: type)
        }
    }

    static func str(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    static func dbl(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
    static func int(_ v: Any?) -> Int? { dbl(v).map { Int($0.rounded()) } }
    static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }
}

/// Splits a byte stream into complete lines. Bytes after the last newline are kept until more arrive,
/// so a UTF-8 character or a JSON object split across reads is never decoded half-way.
public struct JSONLineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<nl]
            pending.removeSubrange(pending.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8) {
                let trimmed = s.hasSuffix("\r") ? String(s.dropLast()) : s
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
        }
        return lines
    }

    /// Returns whatever is left (a final line with no trailing newline).
    public mutating func flush() -> [String] {
        defer { pending = Data() }
        guard !pending.isEmpty, let s = String(data: pending, encoding: .utf8) else { return [] }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? [] : [t]
    }
}

/// Decodes the single JSON document a one-shot `--json` command prints.
/// Tolerates log lines printed before the JSON by falling back to the last line that parses.
public enum JSONOutput {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch let firstError {
            guard let text = String(data: data, encoding: .utf8) else { throw firstError }
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            for line in lines.reversed() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.first == "{" || t.first == "[" else { continue }
                if let d = t.data(using: .utf8), let v = try? decoder.decode(T.self, from: d) { return v }
            }
            // Maybe a pretty-printed document after some log lines: find the first line starting with { or [.
            if let start = lines.firstIndex(where: { $0.first == "{" || $0.first == "[" }) {
                let joined = lines[start...].joined(separator: "\n")
                if let d = joined.data(using: .utf8), let v = try? decoder.decode(T.self, from: d) { return v }
            }
            throw firstError
        }
    }
}
