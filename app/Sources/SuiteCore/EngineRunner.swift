import Foundation
import Darwin

public enum EngineError: LocalizedError, Equatable {
    case uvNotFound(searched: [String])
    case engineNotFound(searched: [String])
    case launchFailed(String)
    case processFailed(command: String, status: Int32, stderr: String)
    case decodeFailed(command: String, detail: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .uvNotFound:
            return "Couldn't find uv, which runs the engine. Install it (curl -LsSf https://astral.sh/uv/install.sh | sh) or set its path in Settings."
        case .engineNotFound:
            return "Couldn't find the engine folder (the one with pyproject.toml). Set it in Settings."
        case .launchFailed(let why):
            return "Couldn't start the engine: \(why)"
        case .processFailed(let command, let status, _):
            return "The engine command “\(command)” failed (exit code \(status))."
        case .decodeFailed(let command, let detail, _):
            return "The engine's reply to “\(command)” wasn't understood: \(detail)"
        }
    }

    /// Extra text worth showing (stderr, searched locations, raw output).
    public var details: String? {
        switch self {
        case .uvNotFound(let searched): return "Looked in:\n" + searched.joined(separator: "\n")
        case .engineNotFound(let searched): return "Looked in:\n" + searched.joined(separator: "\n")
        case .launchFailed: return nil
        case .processFailed(_, _, let stderr): return stderr.isEmpty ? nil : stderr
        case .decodeFailed(_, _, let output): return output.isEmpty ? nil : String(output.prefix(4000))
        }
    }
}

/// Finds `uv` and the engine folder.
public enum EngineLocator {
    public static func uvCandidates(home: String, pathEnv: String?) -> [String] {
        var list = ["\(home)/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv", "\(home)/.cargo/bin/uv"]
        for dir in (pathEnv ?? "").split(separator: ":") where !dir.isEmpty {
            let p = "\(dir)/uv"
            if !list.contains(p) { list.append(p) }
        }
        return list
    }

    public static func resolveUV(override: String?, home: String = NSHomeDirectory(),
                                 pathEnv: String? = ProcessInfo.processInfo.environment["PATH"],
                                 isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) throws -> URL {
        if let o = override?.trimmingCharacters(in: .whitespaces), !o.isEmpty {
            let p = (o as NSString).expandingTildeInPath
            if isExecutable(p) { return URL(fileURLWithPath: p) }
            throw EngineError.uvNotFound(searched: [p + " (from Settings)"])
        }
        let candidates = uvCandidates(home: home, pathEnv: pathEnv)
        if let hit = candidates.first(where: isExecutable) { return URL(fileURLWithPath: hit) }
        throw EngineError.uvNotFound(searched: candidates)
    }

    /// Settings override → SUITE_ENGINE_DIR → bundle Resources/engine → walk up from the executable.
    public static func resolveEngineDir(override: String?, environment: [String: String],
                                        bundleResources: URL?, executable: URL?,
                                        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws -> URL {
        var searched: [String] = []
        func ok(_ dir: URL) -> Bool { fileExists(dir.appendingPathComponent("pyproject.toml").path) }

        if let o = override?.trimmingCharacters(in: .whitespaces), !o.isEmpty {
            let dir = URL(fileURLWithPath: (o as NSString).expandingTildeInPath, isDirectory: true)
            if ok(dir) { return dir }
            searched.append(dir.path + " (from Settings)")
        }
        if let e = environment["SUITE_ENGINE_DIR"], !e.isEmpty {
            let dir = URL(fileURLWithPath: (e as NSString).expandingTildeInPath, isDirectory: true)
            if ok(dir) { return dir }
            searched.append(dir.path + " (SUITE_ENGINE_DIR)")
        }
        if let res = bundleResources {
            let dir = res.appendingPathComponent("engine", isDirectory: true)
            if ok(dir) { return dir }
            searched.append(dir.path)
        }
        if let exe = executable {
            var dir = exe.resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<8 {
                let candidate = dir.appendingPathComponent("engine", isDirectory: true)
                if ok(candidate) { return candidate }
                searched.append(candidate.path)
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        throw EngineError.engineNotFound(searched: searched)
    }
}

/// Runs the `suite` CLI through `uv run --project <engine> suite ...`.
public final class EngineRunner: @unchecked Sendable {
    public struct Config: Sendable {
        public var uvOverride: String?
        public var engineDirOverride: String?
        public var dataFolder: URL
        public var apiKey: String?

        public init(uvOverride: String? = nil, engineDirOverride: String? = nil, dataFolder: URL, apiKey: String? = nil) {
            self.uvOverride = uvOverride; self.engineDirOverride = engineDirOverride
            self.dataFolder = dataFolder; self.apiKey = apiKey
        }
    }

    public let config: Config

    public init(config: Config) { self.config = config }

    private static let activeLock = NSLock()
    nonisolated(unsafe) private static var active: [ObjectIdentifier: Process] = [:]

    static func track(_ p: Process) { activeLock.lock(); active[ObjectIdentifier(p)] = p; activeLock.unlock() }
    static func untrack(_ p: Process) { activeLock.lock(); active[ObjectIdentifier(p)] = nil; activeLock.unlock() }

    /// Stops every one-shot engine command still running (used when the app quits).
    public static func terminateAll() {
        activeLock.lock(); let procs = Array(active.values); activeLock.unlock()
        for p in procs where p.isRunning { p.terminate() }
    }

    public func engineDir() throws -> URL {
        try EngineLocator.resolveEngineDir(override: config.engineDirOverride,
                                           environment: ProcessInfo.processInfo.environment,
                                           bundleResources: Bundle.main.resourceURL,
                                           executable: Bundle.main.executableURL)
    }

    /// Executable, arguments and environment for `suite <args>`.
    public func command(_ args: [String]) throws -> (URL, [String], [String: String]) {
        let uv = try EngineLocator.resolveUV(override: config.uvOverride)
        let engine = try engineDir()
        var env = ProcessInfo.processInfo.environment
        env["SUITE_HOME"] = config.dataFolder.path
        env["UV_PROJECT_ENVIRONMENT"] = config.dataFolder.appendingPathComponent("venv").path
        env["PYTHONUNBUFFERED"] = "1"
        env["UV_NO_PROGRESS"] = "1"
        if let key = config.apiKey, !key.isEmpty { env["ANTHROPIC_API_KEY"] = key }
        // GUI apps get a minimal PATH; make sure uv's usual homes are on it.
        let home = NSHomeDirectory()
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", uv.deletingLastPathComponent().path]
        let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["PATH"] = (extra + [path]).joined(separator: ":")
        // A bundled engine lives inside a signed app: never let uv rewrite its lockfile.
        if engine.path.contains(".app/Contents/Resources"),
           FileManager.default.fileExists(atPath: engine.appendingPathComponent("uv.lock").path) {
            env["UV_FROZEN"] = "1"
        }
        try? FileManager.default.createDirectory(at: config.dataFolder, withIntermediateDirectories: true)
        return (uv, ["run", "--project", engine.path, "suite"] + args, env)
    }

    /// Runs a one-shot command and returns its stdout. Throws with stderr on non-zero exit.
    public func runOnce(_ args: [String]) async throws -> Data {
        let (exe, fullArgs, env) = try command(args)
        let label = "suite " + args.filter { $0 != "--json" }.joined(separator: " ")
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = exe
                p.arguments = fullArgs
                p.environment = env
                p.currentDirectoryURL = self.config.dataFolder
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(throwing: EngineError.launchFailed(error.localizedDescription)); return
                }
                EngineRunner.track(p)
                defer { EngineRunner.untrack(p) }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    cont.resume(throwing: EngineError.processFailed(command: label, status: p.terminationStatus,
                                                                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    cont.resume(returning: outData)
                }
            }
        }
    }

    public func runJSON<T: Decodable>(_ args: [String], as type: T.Type) async throws -> T {
        let data = try await runOnce(args)
        do {
            return try JSONOutput.decode(T.self, from: data)
        } catch {
            let label = "suite " + args.filter { $0 != "--json" }.joined(separator: " ")
            throw EngineError.decodeFailed(command: label, detail: String(describing: error),
                                           output: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Starts a streaming command (`suite run ... --json`). Events arrive on a background queue.
    public func startStreaming(_ args: [String],
                               onEvent: @escaping @Sendable (RunEvent) -> Void,
                               onExit: @escaping @Sendable (_ status: Int32, _ stderr: String) -> Void) throws -> RunningProcess {
        let (exe, fullArgs, env) = try command(args)
        let p = Process()
        p.executableURL = exe
        p.arguments = fullArgs
        p.environment = env
        p.currentDirectoryURL = config.dataFolder
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let queue = DispatchQueue(label: "suite.run.stream")
        let group = DispatchGroup()
        let state = StreamState()

        group.enter()
        out.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            queue.sync {
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    for line in state.buffer.flush() { if let e = RunEventDecoder.decode(line: line) { onEvent(e) } }
                    group.leave()
                } else {
                    for line in state.buffer.append(chunk) { if let e = RunEventDecoder.decode(line: line) { onEvent(e) } }
                }
            }
        }
        group.enter()
        err.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            queue.sync {
                if chunk.isEmpty { h.readabilityHandler = nil; group.leave() }
                else { state.errData.append(chunk); if state.errData.count > 200_000 { state.errData = state.errData.suffix(100_000) } }
            }
        }
        group.enter()
        p.terminationHandler = { _ in group.leave() }

        do { try p.run() } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            throw EngineError.launchFailed(error.localizedDescription)
        }
        group.notify(queue: queue) {
            onExit(p.terminationStatus, String(data: state.errData, encoding: .utf8) ?? "")
        }
        return RunningProcess(process: p)
    }
}

private final class StreamState: @unchecked Sendable {
    var buffer = JSONLineBuffer()
    var errData = Data()
}

public final class RunningProcess: @unchecked Sendable {
    public let process: Process

    init(process: Process) { self.process = process }

    public var isRunning: Bool { process.isRunning }

    /// Sends SIGTERM to the engine. `uv run` is a parent of the Python process, so we signal
    /// uv's children directly (the engine turns SIGTERM into a clean `canceled` finish) and only
    /// signal uv itself if it has no children yet.
    public func cancel() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let children = Self.childPIDs(of: pid)
        if children.isEmpty {
            kill(pid, SIGTERM)
        } else {
            for c in children { kill(c, SIGTERM) }
        }
    }

    static func childPIDs(of pid: pid_t) -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 64)
        let bytes = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        // proc_listchildpids returns a count of pids on recent macOS (bytes on older); handle both.
        let count = Int(bytes) > buf.count ? Int(bytes) / MemoryLayout<pid_t>.size : Int(bytes)
        return Array(buf.prefix(count)).filter { $0 > 0 }
    }
}
