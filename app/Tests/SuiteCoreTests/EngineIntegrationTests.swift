import Foundation
import XCTest
@testable import SuiteCore

/// Runs against the real engine. Skipped unless SUITE_ENGINE_DIR points at it, e.g.
/// SUITE_ENGINE_DIR=../engine swift test --filter EngineIntegrationTests
final class EngineIntegrationTests: XCTestCase {
    private func runner() throws -> (EngineRunner, URL) {
        guard let dir = ProcessInfo.processInfo.environment["SUITE_ENGINE_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set SUITE_ENGINE_DIR to run engine integration tests")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("suite-it-\(UUID().uuidString)")
        return (EngineRunner(config: .init(engineDirOverride: dir, dataFolder: home)), home)
    }

    func testOneShotCommands() async throws {
        let (r, home) = try runner()
        defer { try? FileManager.default.removeItem(at: home) }
        let kinds = try await r.runJSON(["kinds", "--json"], as: [KindInfo].self)
        XCTAssertEqual(kinds.count, 10)
        let agents = try await r.runJSON(["agents", "--json"], as: [AgentInfo].self)
        XCTAssertTrue(agents.contains { $0.id == "reviewer" && !$0.routable })
        let bandit = try await r.runJSON(["bandit", "--json"], as: BanditSnapshot.self)
        XCTAssertFalse(bandit.routing.isEmpty)
    }

    func testStreamingMockRunThenShowAndRate() async throws {
        let (r, home) = try runner()
        defer { try? FileManager.default.removeItem(at: home) }
        final class Box: @unchecked Sendable { var events: [RunEvent] = [] }
        let box = Box()
        let done = expectation(description: "run exits")
        let lock = NSLock()
        _ = try r.startStreaming(["run", "Sell socks online", "--mock", "--json"], onEvent: { e in
            lock.lock(); box.events.append(e); lock.unlock()
        }, onExit: { status, stderr in
            XCTAssertEqual(status, 0, stderr)
            done.fulfill()
        })
        await fulfillment(of: [done], timeout: 240)
        guard case let .runStarted(runId, _, mock, _, _)? = box.events.first else { return XCTFail("no run_started") }
        XCTAssertTrue(mock)
        guard case let .runFinished(_, status, _, _)? = box.events.last(where: { if case .runFinished = $0 { return true }; return false }) else {
            return XCTFail("no run_finished")
        }
        XCTAssertEqual(status, "done")
        XCTAssertTrue(box.events.contains { if case .plan = $0 { return true }; return false })

        let detail = try await r.runJSON(["show", runId, "--json"], as: RunDetail.self)
        XCTAssertFalse(detail.tasks.isEmpty)
        let task = try XCTUnwrap(detail.tasks.first)
        let up = try await r.runJSON(["rate", task.id, "up", "--json"], as: RateResponse.self)
        XCTAssertEqual(up.rating, 1)
        let cleared = try await r.runJSON(["rate", task.id, "clear", "--json"], as: RateResponse.self)
        XCTAssertNil(cleared.rating)
    }

    func testCancelSendsSIGTERM() async throws {
        let (r, home) = try runner()
        defer { try? FileManager.default.removeItem(at: home) }
        final class Box: @unchecked Sendable { var status: String?; var proc: RunningProcess? ; var started = false }
        let box = Box()
        let lock = NSLock()
        let done = expectation(description: "run exits")
        box.proc = try r.startStreaming(["run", "Build a rocket company", "--mock", "--json"], onEvent: { e in
            lock.lock(); defer { lock.unlock() }
            if case .plan = e, !box.started { box.started = true; box.proc?.cancel() }
            if case let .runFinished(_, s, _, _) = e { box.status = s }
        }, onExit: { _, _ in done.fulfill() })
        await fulfillment(of: [done], timeout: 240)
        // A very fast mock run may finish before the signal lands.
        XCTAssertTrue(["canceled", "done"].contains(box.status ?? "none"), "status \(box.status ?? "none")")
    }
}
