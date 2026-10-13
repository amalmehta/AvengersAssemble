import Foundation

// MARK: - Lenient decoding helpers

/// A coding key that accepts any string, so models can look up snake_case keys directly.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

/// Any JSON value, decoded so it can be handed to code that reads Foundation objects.
struct JSONValue: Decodable {
    let foundation: Any

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var dict: [String: Any] = [:]
            for key in keyed.allKeys {
                dict[key.stringValue] = (try? keyed.decode(JSONValue.self, forKey: key))?.foundation ?? NSNull()
            }
            foundation = dict
        } else if var list = try? decoder.unkeyedContainer() {
            var items: [Any] = []
            while !list.isAtEnd { items.append((try? list.decode(JSONValue.self))?.foundation ?? NSNull()) }
            foundation = items
        } else {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() { foundation = NSNull() }
            else if let b = try? single.decode(Bool.self) { foundation = b }
            else if let d = try? single.decode(Double.self) { foundation = NSNumber(value: d) }
            else if let s = try? single.decode(String.self) { foundation = s }
            else { foundation = NSNull() }
        }
    }
}

extension KeyedDecodingContainer where K == AnyKey {
    func string(_ key: String) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: AnyKey(key)) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: AnyKey(key)) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: AnyKey(key)) { return String(d) }
        return nil
    }
    func double(_ key: String) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: AnyKey(key)) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: AnyKey(key)) { return Double(s) }
        return nil
    }
    func int(_ key: String) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: AnyKey(key)) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: AnyKey(key)) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: AnyKey(key)) { return Int(s) }
        return nil
    }
    func bool(_ key: String) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: AnyKey(key)) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: AnyKey(key)) { return i != 0 }
        return nil
    }
    func strings(_ key: String) -> [String] {
        (try? decodeIfPresent([String].self, forKey: AnyKey(key))) ?? []
    }
}

// MARK: - Task

public enum TaskStatus: String, Sendable, CaseIterable, Codable {
    case pending, running, done, failed, skipped

    public init(lenient raw: String?) {
        self = TaskStatus(rawValue: (raw ?? "").lowercased()) ?? .pending
    }

    public var displayName: String {
        switch self {
        case .pending: return "Waiting"
        case .running: return "Working"
        case .done: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    public var symbolName: String {
        switch self {
        case .pending: return "circle.dotted"
        case .running: return "circle.dashed.inset.filled"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "arrow.uturn.right.circle"
        }
    }
}

/// A user's thumbs rating. The engine uses 1 for up, 0 for down and null for none.
public enum UserRating: Sendable, Equatable {
    case up, down

    public init?(engineValue: Int?) {
        guard let v = engineValue else { return nil }
        self = v > 0 ? .up : .down
    }

    public var command: String { self == .up ? "up" : "down" }
}

/// A past task whose wording resembles the one being routed: the evidence text routing leaned on.
public struct SimilarTask: Hashable, Sendable, Identifiable {
    public var taskId: String
    public var title: String
    public var kind: String?
    public var agent: String
    public var variant: String?
    public var reward: Double?
    public var similarity: Double
    public var id: String { taskId }

    public init(taskId: String, title: String, kind: String? = nil, agent: String, variant: String? = nil,
                reward: Double? = nil, similarity: Double) {
        self.taskId = taskId; self.title = title; self.kind = kind; self.agent = agent
        self.variant = variant; self.reward = reward; self.similarity = similarity
    }

    /// From the engine's JSON object; nil when it lacks the essentials.
    public init?(json o: [String: Any]) {
        guard let id = o["task_id"] as? String, let agent = o["agent"] as? String else { return nil }
        self.init(taskId: id, title: o["title"] as? String ?? "Untitled task", kind: o["kind"] as? String,
                  agent: agent, variant: o["variant"] as? String, reward: (o["reward"] as? NSNumber)?.doubleValue,
                  similarity: (o["similarity"] as? NSNumber)?.doubleValue ?? 0)
    }

    public static func list(_ value: Any?) -> [SimilarTask] {
        ((value as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(SimilarTask.init(json:)) }
    }
}

/// Why a task went where it did: each agent's Thompson sample, and the similar past tasks.
public struct RoutingEvidence: Hashable, Sendable {
    public var samples: [String: Double]
    public var similar: [SimilarTask]

    public init(samples: [String: Double] = [:], similar: [SimilarTask] = []) {
        self.samples = samples; self.similar = similar
    }

    public init(json o: [String: Any]) {
        var samples: [String: Double] = [:]
        for (k, v) in (o["samples"] as? [String: Any]) ?? [:] {
            if let d = (v as? NSNumber)?.doubleValue { samples[k] = d }
        }
        self.init(samples: samples, similar: SimilarTask.list(o["similar"]))
    }
}

public struct SuiteTask: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var runId: String?
    public var seq: Int
    public var title: String
    public var description: String?
    public var kind: String
    public var dependsOn: [String]
    public var status: TaskStatus
    public var agent: String?
    public var variant: String?
    public var summary: String?
    public var outputPath: String?
    public var judgeScore: Double?
    public var judgeRationale: String?
    public var userRating: Int?
    public var costUsd: Double?
    public var round: Int?
    /// Stored at dispatch by the engine, so past runs can still explain their routing.
    public var routing: RoutingEvidence?

    public init(id: String, runId: String? = nil, seq: Int, title: String, description: String? = nil,
                kind: String, dependsOn: [String] = [], status: TaskStatus = .pending,
                agent: String? = nil, variant: String? = nil, summary: String? = nil,
                outputPath: String? = nil, judgeScore: Double? = nil, judgeRationale: String? = nil,
                userRating: Int? = nil, costUsd: Double? = nil, round: Int? = 1) {
        self.id = id; self.runId = runId; self.seq = seq; self.title = title
        self.description = description; self.kind = kind; self.dependsOn = dependsOn
        self.status = status; self.agent = agent; self.variant = variant; self.summary = summary
        self.outputPath = outputPath; self.judgeScore = judgeScore; self.judgeRationale = judgeRationale
        self.userRating = userRating; self.costUsd = costUsd; self.round = round
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Task has no id"))
        }
        self.id = id
        runId = c.string("run_id")
        seq = c.int("seq") ?? 0
        title = c.string("title") ?? "Untitled task"
        description = c.string("description")
        kind = c.string("kind") ?? "other"
        dependsOn = c.strings("depends_on")
        status = TaskStatus(lenient: c.string("status"))
        agent = c.string("agent")
        variant = c.string("variant")
        summary = c.string("summary")
        outputPath = c.string("output_path")
        judgeScore = c.double("judge_score")
        judgeRationale = c.string("judge_rationale")
        userRating = c.int("user_rating")
        costUsd = c.double("cost_usd")
        round = c.int("round")
        if let raw = try? c.decodeIfPresent(JSONValue.self, forKey: AnyKey("routing")),
           let obj = raw.foundation as? [String: Any] {
            routing = RoutingEvidence(json: obj)
        }
    }

    public var rating: UserRating? { UserRating(engineValue: userRating) }
}

// MARK: - Runs

public struct RunSummary: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var goal: String
    public var status: String
    public var createdAt: String?
    public var spentUsd: Double
    public var taskCount: Int
    public var mock: Bool
    public var report: String?
    public var workspace: String?

    public init(id: String, goal: String, status: String, createdAt: String? = nil, spentUsd: Double = 0,
                taskCount: Int = 0, mock: Bool = false, report: String? = nil, workspace: String? = nil) {
        self.id = id; self.goal = goal; self.status = status; self.createdAt = createdAt
        self.spentUsd = spentUsd; self.taskCount = taskCount; self.mock = mock
        self.report = report; self.workspace = workspace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Run has no id"))
        }
        self.id = id
        goal = c.string("goal") ?? ""
        status = c.string("status") ?? "unknown"
        createdAt = c.string("created_at")
        spentUsd = c.double("spent_usd") ?? 0
        taskCount = c.int("task_count") ?? 0
        mock = c.bool("mock") ?? false
        report = c.string("report")
        workspace = c.string("workspace")
    }

    public var createdDate: Date? { SuiteDates.parse(createdAt) }
}

public struct RunDetail: Decodable, Sendable {
    public var run: RunSummary
    public var tasks: [SuiteTask]

    public init(run: RunSummary, tasks: [SuiteTask]) { self.run = run; self.tasks = tasks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        run = try c.decode(RunSummary.self, forKey: AnyKey("run"))
        tasks = (try? c.decodeIfPresent([SuiteTask].self, forKey: AnyKey("tasks"))) ?? []
    }
}

public enum RunStatusName {
    public static func display(_ status: String) -> String {
        switch status.lowercased() {
        case "done": return "Finished"
        case "budget": return "Budget reached"
        case "canceled", "cancelled": return "Canceled"
        case "error": return "Error"
        case "running": return "Running"
        case "pending", "starting": return "Starting"
        case "canceling": return "Canceling"
        default: return Naming.humanize(status)
        }
    }
}

public enum SuiteDates {
    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return Date(timeIntervalSince1970: seconds) }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: raw) { return d }
        // Naive timestamps like 2026-10-13T12:00:00 or 2026-10-13 12:00:00.123456
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"] {
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}

// MARK: - Agents, kinds, bandit

public struct AgentInfo: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var skills: [String]
    public var variants: [String]
    public var routable: Bool
    public var path: String?

    public init(id: String, name: String, role: String, skills: [String], variants: [String], routable: Bool = true, path: String? = nil) {
        self.id = id; self.name = name; self.role = role; self.skills = skills
        self.variants = variants; self.routable = routable; self.path = path
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Agent has no id"))
        }
        self.id = id
        name = c.string("name") ?? Naming.defaultAgentName(id)
        role = c.string("role") ?? ""
        skills = c.strings("skills")
        variants = c.strings("variants")
        routable = c.bool("routable") ?? true
        path = c.string("path")
    }
}

public struct KindInfo: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var family: KindFamily

    public init(id: String, name: String, family: KindFamily) { self.id = id; self.name = name; self.family = family }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Kind has no id"))
        }
        self.id = id
        name = c.string("name") ?? KindCatalog.displayName(id)
        family = KindFamily(rawValue: c.string("family") ?? "") ?? KindCatalog.family(of: id)
    }
}

public struct RoutingArm: Decodable, Hashable, Sendable {
    public var kind: String
    public var agent: String
    public var alpha: Double
    public var beta: Double
    public var mean: Double
    public var n: Int

    public init(kind: String, agent: String, alpha: Double, beta: Double, mean: Double? = nil, n: Int) {
        self.kind = kind; self.agent = agent; self.alpha = alpha; self.beta = beta
        self.mean = mean ?? alpha / max(alpha + beta, 1e-9); self.n = n
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        kind = c.string("kind") ?? "other"
        agent = c.string("agent") ?? "unknown"
        alpha = c.double("alpha") ?? 1
        beta = c.double("beta") ?? 1
        mean = c.double("mean") ?? alpha / max(alpha + beta, 1e-9)
        n = c.int("n") ?? 0
    }
}

public struct VariantArm: Decodable, Hashable, Sendable {
    public var agent: String
    public var variant: String
    public var alpha: Double
    public var beta: Double
    public var mean: Double
    public var n: Int

    public init(agent: String, variant: String, alpha: Double, beta: Double, mean: Double? = nil, n: Int) {
        self.agent = agent; self.variant = variant; self.alpha = alpha; self.beta = beta
        self.mean = mean ?? alpha / max(alpha + beta, 1e-9); self.n = n
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        agent = c.string("agent") ?? "unknown"
        variant = c.string("variant") ?? "unknown"
        alpha = c.double("alpha") ?? 1
        beta = c.double("beta") ?? 1
        mean = c.double("mean") ?? alpha / max(alpha + beta, 1e-9)
        n = c.int("n") ?? 0
    }

    /// Standard deviation of the Beta(alpha, beta) posterior.
    public var standardDeviation: Double {
        let s = alpha + beta
        guard s > 0 else { return 0 }
        return (alpha * beta / (s * s * (s + 1))).squareRoot()
    }
}

public struct BanditSnapshot: Decodable, Sendable {
    public var kinds: [String]
    public var routing: [RoutingArm]
    public var variants: [VariantArm]

    public init(kinds: [String], routing: [RoutingArm], variants: [VariantArm]) {
        self.kinds = kinds; self.routing = routing; self.variants = variants
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        kinds = c.strings("kinds")
        routing = (try? c.decodeIfPresent([RoutingArm].self, forKey: AnyKey("routing"))) ?? []
        variants = (try? c.decodeIfPresent([VariantArm].self, forKey: AnyKey("variants"))) ?? []
    }

    public func arm(kind: String, agent: String) -> RoutingArm? {
        routing.first { $0.kind == kind && $0.agent == agent }
    }
}

public struct RateResponse: Decodable, Sendable {
    public var ok: Bool
    public var taskId: String?
    public var rating: Int?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ok = c.bool("ok") ?? false
        taskId = c.string("task_id")
        rating = c.int("rating")
    }
}

// MARK: - Naming

public enum Naming {
    static let agentNames: [String: String] = [
        "ceo": "CEO", "researcher": "Researcher", "marketer": "Marketer",
        "product": "Product Manager", "swe": "Software Engineer", "hardware": "Hardware Engineer",
        "robotics": "Robotics Engineer", "ai": "AI Scientist", "math": "Mathematician",
        "physics": "Physicist", "reviewer": "Reviewer",
    ]

    /// Canonical display order for agents: planner, business, engineering, science, judge.
    public static let agentOrder = ["ceo", "researcher", "marketer", "product", "swe", "hardware", "robotics", "ai", "math", "physics", "reviewer"]

    public static func sortedAgents(_ agents: [AgentInfo]) -> [AgentInfo] {
        agents.sorted { a, b in
            let ia = agentOrder.firstIndex(of: a.id) ?? 999, ib = agentOrder.firstIndex(of: b.id) ?? 999
            return ia != ib ? ia < ib : a.name < b.name
        }
    }

    public static func defaultAgentName(_ id: String) -> String {
        agentNames[id] ?? humanize(id)
    }

    /// "opus-high" → "Opus · High"
    public static func variantName(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "—" }
        return id.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { word in
                let w = String(word)
                if w.lowercased() == "ai" { return "AI" }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " · ")
    }

    /// "user_rating_weight" → "User rating weight"
    public static func humanize(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        guard let first = words.first else { return id }
        return first.uppercased() + words.dropFirst()
    }

    public static func agentSymbol(_ id: String) -> String {
        switch id {
        case "ceo": return "crown"
        case "researcher": return "magnifyingglass"
        case "marketer": return "megaphone"
        case "product": return "shippingbox"
        case "swe": return "chevron.left.forwardslash.chevron.right"
        case "hardware": return "cpu"
        case "robotics": return "gearshape.2"
        case "ai": return "brain"
        case "math": return "function"
        case "physics": return "atom"
        case "reviewer": return "checkmark.seal"
        default: return "person.crop.circle"
        }
    }

    public static func dollars(_ value: Double) -> String {
        value < 10 ? String(format: "$%.2f", value) : String(format: "$%.1f", value)
    }
}
