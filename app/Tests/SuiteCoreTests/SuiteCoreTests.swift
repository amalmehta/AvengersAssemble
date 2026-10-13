import Foundation
import XCTest
@testable import SuiteCore

final class EventDecodingTests: XCTestCase {
    func testRunStarted() {
        let e = RunEventDecoder.decode(line: #"{"type":"run_started","run_id":"r_1","goal":"Sell socks","mock":true,"max_cost_usd":2.0,"max_tasks":40}"#)
        XCTAssertEqual(e, .runStarted(runId: "r_1", goal: "Sell socks", mock: true, maxCostUsd: 2.0, maxTasks: 40))
    }

    func testPlanDecodesTasks() {
        let line = #"""
        {"type":"plan","round":1,"tasks":[{"id":"t_ab12","run_id":"r_1","seq":1,"title":"Size the market","description":"...","kind":"research","depends_on":[],"status":"pending","agent":null,"variant":null,"summary":null,"output_path":null,"judge_score":null,"judge_rationale":null,"user_rating":null,"cost_usd":0,"round":1},{"id":"t_cd34","seq":2,"title":"Pricing","kind":"strategy","depends_on":["t_ab12"],"status":"pending"}]}
        """#
        guard case let .plan(round, tasks)? = RunEventDecoder.decode(line: line) else { return XCTFail("not a plan") }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].id, "t_ab12")
        XCTAssertEqual(tasks[0].kind, "research")
        XCTAssertEqual(tasks[0].status, .pending)
        XCTAssertNil(tasks[0].agent)
        XCTAssertEqual(tasks[1].dependsOn, ["t_ab12"])
    }

    func testTaskAssignedWithSamples() {
        let e = RunEventDecoder.decode(line: #"{"type":"task_assigned","task_id":"t_1","kind":"ai","agent":"ai","variant":"haiku","samples":{"ai":0.8,"swe":0.4}}"#)
        XCTAssertEqual(e, .taskAssigned(taskId: "t_1", kind: "ai", agent: "ai", variant: "haiku", samples: ["ai": 0.8, "swe": 0.4]))
    }

    func testFinishedScoredBudgetRunFinished() {
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"task_finished","task_id":"t_1","status":"done","summary":"ok","output_path":"workspace/tasks/01.md","cost_usd":0.031}"#),
                       .taskFinished(taskId: "t_1", status: .done, summary: "ok", outputPath: "workspace/tasks/01.md", costUsd: 0.031))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"task_scored","task_id":"t_1","score":0.82,"rationale":"good"}"#),
                       .taskScored(taskId: "t_1", score: 0.82, rationale: "good"))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"budget","spent_usd":0.5,"max_cost_usd":2,"tasks_done":3,"max_tasks":40}"#),
                       .budget(spentUsd: 0.5, maxCostUsd: 2, tasksDone: 3, maxTasks: 40))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"run_finished","run_id":"r_1","status":"budget","report_path":"runs/r_1/report.md","spent_usd":2.0}"#),
                       .runFinished(runId: "r_1", status: "budget", reportPath: "runs/r_1/report.md", spentUsd: 2.0))
    }

    func testToolCallAgentTextError() {
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"tool_call","task_id":"t_1","tool":"write_file","summary":"notes.md"}"#),
                       .toolCall(taskId: "t_1", tool: "write_file", summary: "notes.md"))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"agent_text","task_id":"t_1","text":"thinking"}"#),
                       .agentText(taskId: "t_1", text: "thinking"))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"error","message":"boom"}"#), .error(message: "boom"))
    }

    func testUnknownBlankAndGarbage() {
        XCTAssertNil(RunEventDecoder.decode(line: "   "))
        XCTAssertEqual(RunEventDecoder.decode(line: #"{"type":"future_thing","x":1}"#), .unknown(type: "future_thing"))
        XCTAssertEqual(RunEventDecoder.decode(line: "Installing packages…"), .unparsed(line: "Installing packages…"))
        XCTAssertEqual(RunEventDecoder.decode(line: "{not json"), .unparsed(line: "{not json"))
    }

    func testLineBufferSplitsAcrossChunks() {
        var buf = JSONLineBuffer()
        let full = "{\"type\":\"agent_text\",\"task_id\":\"t\",\"text\":\"héllo ✓\"}\n{\"type\":\"error\",\"message\":\"x\"}\r\n{\"type\":"
        let bytes = Array(full.utf8)
        var lines: [String] = []
        // Feed one byte at a time, splitting multibyte characters.
        for b in bytes { lines += buf.append(Data([b])) }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(RunEventDecoder.decode(line: lines[0]), .agentText(taskId: "t", text: "héllo ✓"))
        XCTAssertEqual(RunEventDecoder.decode(line: lines[1]), .error(message: "x"))
        lines = buf.append(Data("\"budget\",\"spent_usd\":1}".utf8))
        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(buf.flush(), ["{\"type\":\"budget\",\"spent_usd\":1}"])
        XCTAssertEqual(buf.flush(), [])
    }
}

final class CommandOutputDecodingTests: XCTestCase {
    func testRuns() throws {
        let json = #"[{"id":"r_2","goal":"B","status":"running","created_at":"2026-10-13T10:00:00Z","spent_usd":0.1,"task_count":2,"mock":true},{"id":"r_1","goal":"A","status":"done","created_at":"2026-10-12T10:00:00","spent_usd":1,"task_count":5,"mock":false}]"#
        let runs = try JSONOutput.decode([RunSummary].self, from: Data(json.utf8))
        XCTAssertEqual(runs.map(\.id), ["r_2", "r_1"])
        XCTAssertEqual(runs[0].mock, true)
        XCTAssertNotNil(runs[0].createdDate)
        XCTAssertNotNil(runs[1].createdDate)
    }

    func testShowWithLogLinesBefore() throws {
        let out = """
        warning: something from a library
        {"run": {"id":"r_1","goal":"A","status":"done","created_at":"x","spent_usd":1.2,"task_count":1,"mock":false,"report":"# Hi","workspace":"/tmp/runs/r_1/workspace"}, "tasks": [{"id":"t_1","seq":1,"title":"T","kind":"math","status":"done","judge_score":0.9,"user_rating":0}]}
        """
        let d = try JSONOutput.decode(RunDetail.self, from: Data(out.utf8))
        XCTAssertEqual(d.run.report, "# Hi")
        XCTAssertEqual(d.tasks.first?.judgeScore, 0.9)
        XCTAssertEqual(d.tasks.first?.rating, .down)
    }

    func testAgentsBanditKindsRate() throws {
        let agents = try JSONOutput.decode([AgentInfo].self, from: Data(#"[{"id":"swe","name":"Software Engineer","role":"Writes code","skills":["software","ai"],"variants":["opus-high","haiku"],"routable":true,"path":"/x/swe.yaml"},{"id":"reviewer","name":"Reviewer","role":"Judge","skills":[],"variants":["sonnet-medium"],"routable":false,"path":"/x/r.yaml"}]"#.utf8))
        XCTAssertEqual(agents.count, 2)
        XCTAssertFalse(agents[1].routable)

        let bandit = try JSONOutput.decode(BanditSnapshot.self, from: Data(#"{"kinds":["software"],"routing":[{"kind":"software","agent":"swe","alpha":3,"beta":1,"mean":0.75,"n":2}],"variants":[{"agent":"swe","variant":"haiku","alpha":2.5,"beta":1.5,"mean":0.625,"n":2.0}]}"#.utf8))
        XCTAssertEqual(bandit.arm(kind: "software", agent: "swe")?.mean, 0.75)
        XCTAssertEqual(bandit.variants.first?.n, 2)
        XCTAssertGreaterThan(bandit.variants.first?.standardDeviation ?? 0, 0)

        let kinds = try JSONOutput.decode([KindInfo].self, from: Data(#"[{"id":"strategy","name":"Strategy","family":"business"},{"id":"chemistry","name":"Chemistry","family":"science"}]"#.utf8))
        XCTAssertEqual(kinds[1].family, .science)

        let rate = try JSONOutput.decode(RateResponse.self, from: Data(#"{"ok":true,"task_id":"t_1","rating":null}"#.utf8))
        XCTAssertTrue(rate.ok)
        XCTAssertNil(rate.rating)
    }

    func testNaming() {
        XCTAssertEqual(Naming.variantName("opus-high"), "Opus · High")
        XCTAssertEqual(Naming.variantName("haiku"), "Haiku")
        XCTAssertEqual(Naming.defaultAgentName("swe"), "Software Engineer")
        XCTAssertEqual(Naming.humanize("user_rating_weight"), "User rating weight")
        XCTAssertEqual(KindCatalog.displayName("ai"), "AI")
        XCTAssertEqual(RunStatusName.display("budget"), "Budget reached")
    }
}

final class PaletteTests: XCTestCase {
    private let families: [KindFamily: [String]] = [
        .business: ["strategy", "marketing", "product"],
        .engineering: ["software", "hardware", "robotics"],
        .science: ["research", "ai", "math", "physics"],
    ]

    func testEveryKindHasASwatch() {
        for k in KindCatalog.defaults { XCTAssertNotNil(KindPalette.swatches[k.id], k.id) }
    }

    func testFamiliesShareHueRanges() {
        for (family, kinds) in families {
            let range = KindPalette.familyHueRanges[family]!
            for k in kinds {
                let s = KindPalette.swatches[k]!
                for (mode, c) in [("light", s.light), ("dark", s.dark)] {
                    let h = c.hsb.hue
                    XCTAssertTrue(range.contains(h), "\(k) \(mode) hue \(h) outside \(family) range \(range)")
                    XCTAssertGreaterThan(c.hsb.saturation, 0.35, "\(k) \(mode) is too grey to read as its family")
                }
            }
        }
    }

    func testFamilyRangesDoNotOverlap() {
        let ranges = KindPalette.familyHueRanges.values.sorted { $0.lowerBound < $1.lowerBound }
        for (a, b) in zip(ranges, ranges.dropFirst()) { XCTAssertLessThan(a.upperBound, b.lowerBound) }
    }

    func testSiblingsAreDistinguishable() {
        for (_, kinds) in families {
            for i in kinds.indices {
                for j in kinds.indices where j > i {
                    let a = KindPalette.swatches[kinds[i]]!, b = KindPalette.swatches[kinds[j]]!
                    for (mode, x, y) in [("light", a.light, b.light), ("dark", a.dark, b.dark)] {
                        let dh = RGB.hueDistance(x.hsb.hue, y.hsb.hue)
                        XCTAssertGreaterThanOrEqual(dh, 14, "\(kinds[i]) vs \(kinds[j]) (\(mode)) hues only \(dh)° apart")
                        XCTAssertGreaterThan(x.distance(to: y), 0.15, "\(kinds[i]) vs \(kinds[j]) (\(mode)) too similar")
                    }
                }
            }
        }
    }

    func testLightValuesReadOnLightAndDarkValuesReadOnDark() {
        let white = RGB(r: 1, g: 1, b: 1).luminance
        let darkBg = RGB(hex: 0x1E1E1E).luminance
        for (k, s) in KindPalette.swatches {
            let lightContrast = (white + 0.05) / (s.light.luminance + 0.05)
            let darkContrast = (s.dark.luminance + 0.05) / (darkBg + 0.05)
            XCTAssertGreaterThan(lightContrast, 2.6, "\(k) light text too faint on white (\(lightContrast))")
            XCTAssertGreaterThan(darkContrast, 4.5, "\(k) dark text too faint on dark (\(darkContrast))")
            XCTAssertGreaterThan(s.dark.hsb.brightness, s.light.hsb.brightness - 0.05, "\(k) dark value should be lighter")
        }
    }

    func testUnknownKindFallsBackToFamily() {
        XCTAssertEqual(KindPalette.swatch(for: "chemistry", family: .science), KindPalette.swatches["ai"])
        XCTAssertEqual(KindPalette.swatch(for: "astrology"), KindPalette.neutral)
    }
}

final class StorageTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("suite-tests-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testSettingsMergeKeepsUnknownKeys() throws {
        let url = tmp.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data(#"{"mock": true, "theme": "dusk", "max_tasks": 12}"#.utf8).write(to: url)
        var s = SettingsFile.load(from: url)
        XCTAssertEqual(s.maxTasks, 12)
        XCTAssertEqual(s.maxCostUsd, 2.0)
        s.mock = false
        s.maxCostUsd = 5.5
        try SettingsFile.save(s, to: url)
        let raw = SettingsFile.readRaw(from: url)
        XCTAssertEqual(raw["theme"] as? String, "dusk")
        XCTAssertEqual(raw["mock"] as? Bool, false)
        XCTAssertEqual((raw["max_cost_usd"] as? NSNumber)?.doubleValue, 5.5)
        XCTAssertEqual((raw["max_agent_steps"] as? NSNumber)?.intValue, 10)
        XCTAssertEqual((raw["max_parallel_tasks"] as? NSNumber)?.intValue, 3)
        try Data(#"{"max_parallel_tasks": 5}"#.utf8).write(to: url)
        XCTAssertEqual(SettingsFile.load(from: url).maxParallelTasks, 5)
    }

    func testFeedbackAppends() throws {
        try FeedbackLog.append(text: "one", appVersion: "1.0", dataFolder: tmp)
        try FeedbackLog.append(text: "two \"quoted\"", appVersion: "1.0", dataFolder: tmp)
        let lines = try String(contentsOf: tmp.appendingPathComponent("feedback.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let obj = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        XCTAssertEqual(obj?["text"] as? String, "two \"quoted\"")
        XCTAssertEqual(obj?["app_version"] as? String, "1.0")
        XCTAssertNotNil(obj?["date"])
    }

    func testDataFolderAndOutputPaths() {
        XCTAssertEqual(SuitePaths.dataFolder(environment: ["SUITE_HOME": "/tmp/sh"]).path, "/tmp/sh")
        XCTAssertTrue(SuitePaths.dataFolder(environment: [:]).path.hasSuffix("Application Support/Suite of Agents"))
        let run = SuitePaths.runFolder(dataFolder: URL(fileURLWithPath: "/d"), runId: "r_1")
        XCTAssertEqual(SuitePaths.outputURL(outputPath: "workspace/tasks/01.md", runFolder: run).path, "/d/runs/r_1/workspace/tasks/01.md")
    }

    func testEngineDirResolutionOrder() throws {
        let existing: Set<String> = ["/override/pyproject.toml", "/env/pyproject.toml", "/App.app/Contents/Resources/engine/pyproject.toml", "/repo/engine/pyproject.toml"]
        let exists: (String) -> Bool = { existing.contains($0) }
        let res = URL(fileURLWithPath: "/App.app/Contents/Resources")
        let exe = URL(fileURLWithPath: "/repo/app/.build/debug/SuiteOfAgents")
        XCTAssertEqual(try EngineLocator.resolveEngineDir(override: "/override", environment: ["SUITE_ENGINE_DIR": "/env"], bundleResources: res, executable: exe, fileExists: exists).path, "/override")
        XCTAssertEqual(try EngineLocator.resolveEngineDir(override: "", environment: ["SUITE_ENGINE_DIR": "/env"], bundleResources: res, executable: exe, fileExists: exists).path, "/env")
        XCTAssertEqual(try EngineLocator.resolveEngineDir(override: nil, environment: [:], bundleResources: res, executable: exe, fileExists: exists).path, "/App.app/Contents/Resources/engine")
        XCTAssertEqual(try EngineLocator.resolveEngineDir(override: nil, environment: [:], bundleResources: nil, executable: exe, fileExists: exists).path, "/repo/engine")
        XCTAssertThrowsError(try EngineLocator.resolveEngineDir(override: nil, environment: [:], bundleResources: nil, executable: URL(fileURLWithPath: "/x/y"), fileExists: exists))
    }

    func testUVResolution() throws {
        let uv = try EngineLocator.resolveUV(override: nil, home: "/h", pathEnv: "/usr/bin:/custom", isExecutable: { $0 == "/custom/uv" })
        XCTAssertEqual(uv.path, "/custom/uv")
        let first = try EngineLocator.resolveUV(override: nil, home: "/h", pathEnv: nil, isExecutable: { $0 == "/h/.local/bin/uv" || $0 == "/usr/local/bin/uv" })
        XCTAssertEqual(first.path, "/h/.local/bin/uv")
        XCTAssertThrowsError(try EngineLocator.resolveUV(override: "/nope/uv", home: "/h", pathEnv: nil, isExecutable: { _ in true && false }))
    }
}
