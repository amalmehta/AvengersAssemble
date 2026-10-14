import AppKit
import Observation
import SuiteCore
import SwiftUI

enum SidebarItem: Hashable {
    case newRun, team, bandit
    case run(String)
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var details: String?
}

struct ActivityNote: Identifiable, Equatable {
    let id = UUID()
    var date = Date()
    var icon: String
    var text: String
}

/// Everything shown for one run, live or loaded from `suite show`.
@Observable
final class RunState: Identifiable {
    var id: String
    var goal: String
    var status: String
    var isLive: Bool
    var mock: Bool
    var createdAt: Date?
    var tasks: [SuiteTask] = []
    var spentUsd: Double = 0
    var maxCostUsd: Double
    var tasksDone: Int = 0
    var maxTasks: Int
    var report: String?
    var runFolder: URL?
    var activity: [String: [ActivityNote]] = [:]
    var samples: [String: [String: Double]] = [:]
    var similar: [String: [SimilarTask]] = [:]
    var selectedTaskID: String?
    var loading = false

    init(id: String, goal: String, status: String, isLive: Bool, mock: Bool, maxCostUsd: Double, maxTasks: Int) {
        self.id = id; self.goal = goal; self.status = status; self.isLive = isLive
        self.mock = mock; self.maxCostUsd = maxCostUsd; self.maxTasks = maxTasks
    }

    var isActive: Bool { isLive && ["starting", "running", "canceling"].contains(status) }

    func index(of taskID: String) -> Int? { tasks.firstIndex { $0.id == taskID } }

    func apply(detail: RunDetail, dataFolder: URL) {
        goal = detail.run.goal
        status = detail.run.status
        mock = detail.run.mock
        spentUsd = detail.run.spentUsd
        createdAt = detail.run.createdDate ?? createdAt
        report = detail.run.report ?? report
        // Keep task-local live state (activity) but take the engine's view of every task.
        tasks = detail.tasks.sorted { $0.seq < $1.seq }
        for t in tasks {  // routing evidence stored by the engine; live events already filled it in for this session
            guard let r = t.routing else { continue }
            if samples[t.id] == nil, !r.samples.isEmpty { samples[t.id] = r.samples }
            if similar[t.id] == nil { similar[t.id] = r.similar }
        }
        tasksDone = tasks.filter { $0.status == .done || $0.status == .failed }.count
        if let ws = detail.run.workspace, !ws.isEmpty {
            runFolder = URL(fileURLWithPath: ws).deletingLastPathComponent()
        } else {
            runFolder = SuitePaths.runFolder(dataFolder: dataFolder, runId: id)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    // Sidebar + content
    var selection: SidebarItem? = .newRun
    var runs: [RunSummary] = []
    var agents: [AgentInfo] = []
    var kinds: [KindInfo] = KindCatalog.defaults
    var bandit: BanditSnapshot?
    var loadedRuns: [String: RunState] = [:]
    var liveRun: RunState?
    var banner: Banner?
    var isRefreshing = false
    var loadedOnce = false

    // New Run
    var draftGoal = ""
    var attachments: [URL] = []
    var dropTargeted = false

    // Settings
    var settings: EngineSettings
    var hasAPIKey: Bool
    var uvOverride: String { didSet { UserDefaults.standard.set(uvOverride, forKey: "uvPathOverride") } }
    var engineDirOverride: String { didSet { UserDefaults.standard.set(engineDirOverride, forKey: "engineDirOverride") } }

    let dataFolder: URL
    let isDemo: Bool
    @ObservationIgnored private var running: RunningProcess?

    init(demo: Bool = false) {
        isDemo = demo
        dataFolder = SuitePaths.dataFolder()
        // Preferences saved under the app's old bundle ID carry over once.
        if let legacy = UserDefaults(suiteName: AppInfo.legacyBundleID) {
            for key in ["uvPathOverride", "engineDirOverride"] where UserDefaults.standard.object(forKey: key) == nil {
                if let value = legacy.string(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
            }
        }
        uvOverride = UserDefaults.standard.string(forKey: "uvPathOverride") ?? ""
        engineDirOverride = UserDefaults.standard.string(forKey: "engineDirOverride") ?? ""
        if demo {
            settings = EngineSettings()
            hasAPIKey = false
            loadDemo()
        } else {
            settings = SettingsFile.load(from: SettingsFile.url(in: dataFolder))
            hasAPIKey = Keychain.read() != nil
        }
    }

    // MARK: Names

    func agentName(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "Unassigned" }
        return agents.first { $0.id == id }?.name ?? Naming.defaultAgentName(id)
    }

    func kindName(_ id: String) -> String {
        kinds.first { $0.id == id }?.name ?? KindCatalog.displayName(id)
    }

    func kindFamily(_ id: String) -> KindFamily {
        kinds.first { $0.id == id }?.family ?? KindCatalog.family(of: id)
    }

    /// Mock is forced on when no API key is available.
    var effectiveMock: Bool {
        settings.mock || (!hasAPIKey && (ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "").isEmpty)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: Engine

    func runner() -> EngineRunner {
        EngineRunner(config: .init(uvOverride: uvOverride, engineDirOverride: engineDirOverride,
                                   dataFolder: dataFolder, apiKey: Keychain.read()))
    }

    func show(_ error: Error, title: String) {
        if let e = error as? EngineError {
            banner = Banner(title: title, message: e.errorDescription ?? "\(e)", details: e.details)
        } else {
            banner = Banner(title: title, message: error.localizedDescription, details: nil)
        }
    }

    func refreshAll() async {
        guard !isDemo, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; loadedOnce = true }
        let r = runner()
        do {
            kinds = try await r.runJSON(["kinds", "--json"], as: [KindInfo].self)
            agents = Naming.sortedAgents(try await r.runJSON(["agents", "--json"], as: [AgentInfo].self))
            runs = try await r.runJSON(["runs", "--json"], as: [RunSummary].self)
            bandit = try await r.runJSON(["bandit", "--json"], as: BanditSnapshot.self)
        } catch {
            if kinds.isEmpty { kinds = KindCatalog.defaults }
            show(error, title: "Couldn't load from the engine")
        }
    }

    func refreshRunsAndBandit() async {
        guard !isDemo else { return }
        let r = runner()
        if let v = try? await r.runJSON(["runs", "--json"], as: [RunSummary].self) { runs = v }
        if let v = try? await r.runJSON(["bandit", "--json"], as: BanditSnapshot.self) { bandit = v }
    }

    func runState(for id: String) -> RunState? {
        if let live = liveRun, live.id == id { return live }
        return loadedRuns[id]
    }

    func loadRun(_ id: String) async {
        guard !isDemo else { return }
        let state: RunState
        if let existing = runState(for: id) {
            state = existing
        } else {
            let summary = runs.first { $0.id == id }
            state = RunState(id: id, goal: summary?.goal ?? "", status: summary?.status ?? "done", isLive: false,
                             mock: summary?.mock ?? false, maxCostUsd: settings.maxCostUsd, maxTasks: settings.maxTasks)
            state.createdAt = summary?.createdDate
            loadedRuns[id] = state
        }
        state.loading = true
        defer { state.loading = false }
        do {
            let detail = try await runner().runJSON(["show", id, "--json"], as: RunDetail.self)
            state.apply(detail: detail, dataFolder: dataFolder)
            if state.selectedTaskID == nil { state.selectedTaskID = state.tasks.first?.id }
        } catch {
            show(error, title: "Couldn't open that run")
        }
    }

    // MARK: Runs

    var canStart: Bool {
        !draftGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(liveRun?.isActive ?? false)
    }

    func startRun() {
        guard canStart, !isDemo else { return }
        let goal = draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["run", goal]
        for url in attachments { args += ["--input", url.path] }
        if effectiveMock { args.append("--mock") }
        args.append("--json")

        let state = RunState(id: "pending-\(UUID().uuidString.prefix(6))", goal: goal, status: "starting", isLive: true,
                             mock: effectiveMock, maxCostUsd: settings.maxCostUsd, maxTasks: settings.maxTasks)
        state.createdAt = Date()
        do {
            running = try runner().startStreaming(args, onEvent: { [weak self] event in
                Task { @MainActor in self?.apply(event, to: state) }
            }, onExit: { [weak self] status, stderr in
                Task { @MainActor in self?.runExited(state, status: status, stderr: stderr) }
            })
        } catch {
            show(error, title: "Couldn't start the run")
            return
        }
        liveRun = state
        selection = .run(state.id)
        draftGoal = ""
        attachments = []
    }

    func cancelRun() {
        guard let live = liveRun, live.isActive else { return }
        live.status = "canceling"
        running?.cancel()
    }

    func apply(_ event: RunEvent, to state: RunState) {
        switch event {
        case let .runStarted(runId, goal, mock, maxCost, maxTasks):
            let wasSelected = selection == .run(state.id)
            if !runId.isEmpty { state.id = runId }
            if !goal.isEmpty { state.goal = goal }
            state.mock = mock
            state.status = "running"
            if let maxCost { state.maxCostUsd = maxCost }
            if let maxTasks { state.maxTasks = maxTasks }
            state.runFolder = SuitePaths.runFolder(dataFolder: dataFolder, runId: state.id)
            if wasSelected { selection = .run(state.id) }
        case let .plan(_, tasks):
            for t in tasks {
                if let i = state.index(of: t.id) { state.tasks[i] = t } else { state.tasks.append(t) }
            }
            state.tasks.sort { $0.seq < $1.seq }
            if state.selectedTaskID == nil { state.selectedTaskID = state.tasks.first?.id }
        case let .taskAssigned(taskId, kind, agent, variant, samples, similar):
            if let i = state.index(of: taskId) {
                state.tasks[i].agent = agent
                state.tasks[i].variant = variant
                if let kind { state.tasks[i].kind = kind }
                if state.tasks[i].status == .pending { state.tasks[i].status = .running }
            }
            state.samples[taskId] = samples
            state.similar[taskId] = similar
            note(state, taskId, "person.crop.circle.badge.checkmark", "Assigned to \(agentName(agent)) on \(Naming.variantName(variant))")
            state.selectedTaskID = taskId
        case let .toolCall(taskId, tool, summary):
            note(state, taskId, "wrench.and.screwdriver", summary.isEmpty ? Naming.humanize(tool) : "\(Naming.humanize(tool)): \(summary)")
        case let .agentText(taskId, text):
            note(state, taskId, "text.bubble", text)
        case let .taskFinished(taskId, status, summary, outputPath, cost):
            if let i = state.index(of: taskId) {
                state.tasks[i].status = status
                if let summary { state.tasks[i].summary = summary }
                if let outputPath { state.tasks[i].outputPath = outputPath }
                if let cost { state.tasks[i].costUsd = cost }
            }
        case let .taskScored(taskId, score, rationale):
            if let i = state.index(of: taskId) {
                state.tasks[i].judgeScore = score
                state.tasks[i].judgeRationale = rationale
            }
        case let .budget(spent, maxCost, done, maxTasks):
            state.spentUsd = spent
            state.tasksDone = done
            if let maxCost { state.maxCostUsd = maxCost }
            if let maxTasks { state.maxTasks = maxTasks }
        case let .runFinished(_, status, reportPath, spent):
            state.status = status
            if let spent { state.spentUsd = spent }
            if let reportPath { state.report = readReport(reportPath, state: state) ?? state.report }
        case let .error(message):
            banner = Banner(title: "The engine reported an error", message: message, details: nil)
        case .unknown, .unparsed:
            break
        }
    }

    private func note(_ state: RunState, _ taskId: String, _ icon: String, _ text: String) {
        state.activity[taskId, default: []].append(ActivityNote(icon: icon, text: text))
        if state.activity[taskId]!.count > 200 { state.activity[taskId]!.removeFirst() }
    }

    private func readReport(_ path: String, state: RunState) -> String? {
        let candidates: [URL] = path.hasPrefix("/")
            ? [URL(fileURLWithPath: path)]
            : [state.runFolder?.appendingPathComponent(path), dataFolder.appendingPathComponent(path)].compactMap { $0 }
        for url in candidates { if let s = try? String(contentsOf: url, encoding: .utf8) { return s } }
        return nil
    }

    private func runExited(_ state: RunState, status: Int32, stderr: String) {
        running = nil
        if state.isActive {
            // The stream ended without run_finished.
            state.status = state.status == "canceling" ? "canceled" : "error"
            let tail = stderr.split(separator: "\n").suffix(40).joined(separator: "\n")
            banner = Banner(title: "The run stopped unexpectedly",
                            message: "The engine exited with code \(status) before finishing the run.",
                            details: tail.isEmpty ? nil : tail)
        }
        Task {
            await refreshRunsAndBandit()
            if !state.id.hasPrefix("pending-") { await loadRun(state.id) }
        }
    }

    func rate(_ task: SuiteTask, _ rating: UserRating, in state: RunState) {
        let current = task.rating
        let command = current == rating ? "clear" : rating.command
        let newValue: Int? = command == "clear" ? nil : (rating == .up ? 1 : 0)
        if let i = state.index(of: task.id) { state.tasks[i].userRating = newValue }
        guard !isDemo else { return }
        Task {
            do {
                let res = try await runner().runJSON(["rate", task.id, command, "--json"], as: RateResponse.self)
                if let i = state.index(of: task.id) { state.tasks[i].userRating = res.rating }
                if let v = try? await runner().runJSON(["bandit", "--json"], as: BanditSnapshot.self) { bandit = v }
            } catch {
                if let i = state.index(of: task.id) { state.tasks[i].userRating = current.map { $0 == .up ? 1 : 0 } }
                show(error, title: "Couldn't save your rating")
            }
        }
    }

    func terminate() {
        running?.cancel()
        EngineRunner.terminateAll()
    }

    // MARK: Files

    func attach(_ urls: [URL]) {
        for url in urls where !attachments.contains(url) { attachments.append(url) }
        selection = .newRun
    }

    func detach(_ url: URL) { attachments.removeAll { $0 == url } }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        panel.message = "Choose files for the agents to work with"
        if panel.runModal() == .OK { attach(panel.urls) }
    }

    /// Writes pasted or dropped image data to a temp file so it can be passed as --input.
    func writeTempImage(_ data: Data, ext: String = "png") -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var url = dir.appendingPathComponent("Pasted Image \(f.string(from: Date())).\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("Pasted Image \(f.string(from: Date())) \(i).\(ext)"); i += 1
        }
        do { try data.write(to: url); return url } catch { return nil }
    }

    /// Handles ⌘V. Returns true if the pasteboard held files or an image we attached.
    func pasteFromPasteboard(_ pb: NSPasteboard = .general) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            attach(urls)
            return true
        }
        let hasText = pb.availableType(from: [.string]) != nil
        if !hasText, let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]),
           let url = writeTempImage(png) {
            attach([url])
            return true
        }
        return false
    }

    func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            banner = Banner(title: "File not found", message: "There's no file at \(url.path) yet.", details: nil)
        }
    }

    func revealDataFolder() {
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
    }

    func openAgentsFolder() {
        let dir = dataFolder.appendingPathComponent("agents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: Settings

    func saveSettings() {
        guard !isDemo else { return }
        do { try SettingsFile.save(settings, to: SettingsFile.url(in: dataFolder)) }
        catch { show(error, title: "Couldn't save settings") }
    }

    func saveAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isDemo else { return false }
        let ok = Keychain.save(trimmed)
        hasAPIKey = Keychain.read() != nil
        return ok
    }

    func removeAPIKey() {
        guard !isDemo else { return }
        Keychain.delete()
        hasAPIKey = false
    }

    func sendFeedback(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if isDemo { return true }
        do { try FeedbackLog.append(text: t, appVersion: appVersion, dataFolder: dataFolder); return true }
        catch { show(error, title: "Couldn't save feedback"); return false }
    }

    // MARK: Demo

    private func loadDemo() {
        agents = DemoData.agents
        runs = DemoData.runs
        bandit = DemoData.bandit
        let s = RunState(id: DemoData.runId, goal: DemoData.goal, status: "done", isLive: false, mock: false,
                         maxCostUsd: 2.0, maxTasks: 40)
        s.tasks = DemoData.tasks
        s.spentUsd = 1.57
        s.tasksDone = DemoData.tasks.count
        s.report = DemoData.report
        s.samples = DemoData.samples
        s.similar = DemoData.similar
        s.createdAt = SuiteDates.parse("2026-10-13T16:42:00Z")
        s.selectedTaskID = "t_04"
        s.runFolder = URL(fileURLWithPath: "/tmp")
        loadedRuns[s.id] = s
        loadedOnce = true
        draftGoal = "Launch a company selling a home robot that folds laundry. Start with the US market and keep the first version under $1,200."
        attachments = [URL(fileURLWithPath: "/Users/demo/Desktop/competitor-teardown.pdf"),
                       URL(fileURLWithPath: "/Users/demo/Desktop/fold-prototype.mov"),
                       URL(fileURLWithPath: "/Users/demo/Desktop/survey-results.csv")]
    }
}
