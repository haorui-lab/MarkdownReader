import XCTest
@testable import MarkdownReader

/// 纯路由引擎测试：不依赖 AppKit/SwiftUI，只验证决策逻辑。
final class WindowRoutingEngineTests: TemporaryDirectoryTestCase {

    private let engine = WindowRoutingEngine()
    private let identityService = ResourceIdentityService()

    private func file(_ name: String, content: String = "x") -> ResourceIdentity {
        let url = (try? makeFile(named: name, content: content)) ?? temporaryDirectory!.appendingPathComponent(name)
        return try! identityService.identity(for: url, kind: .file)
    }

    private func directory(_ name: String) -> ResourceIdentity {
        let url = (try? makeDirectory(named: name)) ?? temporaryDirectory!.appendingPathComponent(name)
        return try! identityService.identity(for: url, kind: .directory)
    }

    // MARK: - 空白窗口复用

    func testNewResourceReusesPreferredBlankSession() {
        let blank = WindowID()
        var state = WindowRoutingState()
        state.sessions[blank] = SessionRoutingSnapshot(id: blank, isBlank: true)

        let decision = engine.decision(
            for: file("a.md"),
            preferredWindowID: blank,
            state: state
        )

        if case .openInSession(let windowID, _) = decision {
            XCTAssertEqual(windowID, blank)
        } else {
            XCTFail("expected .openInSession(blank), got \(decision)")
        }
    }

    func testNewResourceCreatesWindowWhenPreferredSessionIsOccupied() {
        let occupied = WindowID()
        var state = WindowRoutingState()
        // preferred 窗口非空白 → 不能复用
        state.sessions[occupied] = SessionRoutingSnapshot(id: occupied, isBlank: false)

        let resource = file("a.md")
        let decision = engine.decision(
            for: resource,
            preferredWindowID: occupied,
            state: state,
            makeWindowID: { WindowID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) }
        )

        if case .createWindow(let windowID, _) = decision {
            XCTAssertNotEqual(windowID, occupied)
        } else {
            XCTFail("expected .createWindow, got \(decision)")
        }
    }

    // MARK: - 激活 owner

    func testOwnedFileActivatesOwner() {
        let owner = WindowID()
        let resource = file("a.md")
        var state = WindowRoutingState()
        state.sessions[owner] = SessionRoutingSnapshot(id: owner, isBlank: false)
        state.owners[resource] = owner

        let decision = engine.decision(
            for: resource,
            preferredWindowID: WindowID(),
            state: state
        )

        if case .activateOwner(let windowID, let res) = decision {
            XCTAssertEqual(windowID, owner)
            XCTAssertEqual(res, resource)
        } else {
            XCTFail("expected .activateOwner, got \(decision)")
        }
    }

    func testOwnedDirectoryActivatesOwner() {
        let owner = WindowID()
        let resource = directory("notes")
        var state = WindowRoutingState()
        state.sessions[owner] = SessionRoutingSnapshot(id: owner, isBlank: false)
        state.owners[resource] = owner

        let decision = engine.decision(for: resource, preferredWindowID: nil, state: state)

        if case .activateOwner(let windowID, _) = decision {
            XCTAssertEqual(windowID, owner)
        } else {
            XCTFail("expected .activateOwner, got \(decision)")
        }
    }

    // MARK: - 去重

    func testDuplicateURLsInOneRequestProduceOneDecision() {
        let resource = file("dup.md")
        let decisions = engine.decisions(
            for: [resource, resource, resource],
            preferredWindowID: nil,
            state: WindowRoutingState(),
            makeWindowID: { WindowID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!) }
        )

        XCTAssertEqual(decisions.count, 1, "重复资源只应产生一个决策")
    }

    func testMultipleNewURLsReuseOneBlankThenCreateWindows() {
        let blank = WindowID()
        var state = WindowRoutingState()
        state.sessions[blank] = SessionRoutingSnapshot(id: blank, isBlank: true)

        let a = file("a.md")
        let b = file("b.md")
        let c = file("c.md")

        let decisions = engine.decisions(
            for: [a, b, c],
            preferredWindowID: blank,
            state: state,
            makeWindowID: { WindowID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!) }
        )

        // 第一个新资源复用空白窗口；后两个各自创建窗口。
        guard decisions.count == 3 else {
            return XCTFail("expected 3 decisions, got \(decisions.count)")
        }
        if case .openInSession(let w, _) = decisions[0] {
            XCTAssertEqual(w, blank)
        } else {
            XCTFail("first should reuse blank, got \(decisions[0])")
        }
        for d in decisions.dropFirst() {
            if case .createWindow = d { continue }
            XCTFail("expected .createWindow, got \(d)")
        }
    }

    // MARK: - owner 冲突不重分配

    func testOwnerConflictDoesNotReassignResource() {
        let owner = WindowID()
        let resource = file("owned.md")
        var state = WindowRoutingState()
        state.sessions[owner] = SessionRoutingSnapshot(id: owner, isBlank: false)
        state.owners[resource] = owner

        // 即使指定另一个 preferredWindowID，已有 owner 时仍激活 owner，不重分配。
        let other = WindowID()
        let decision = engine.decision(
            for: resource,
            preferredWindowID: other,
            state: state
        )

        if case .activateOwner(let windowID, _) = decision {
            XCTAssertEqual(windowID, owner)
            XCTAssertNotEqual(windowID, other)
        } else {
            XCTFail("expected .activateOwner, got \(decision)")
        }
    }

    // MARK: - 任意可复用 blank

    func testFallsBackToAnyBlankWhenPreferredNotProvided() {
        let blank = WindowID()
        var state = WindowRoutingState()
        state.sessions[blank] = SessionRoutingSnapshot(id: blank, isBlank: true)

        let decision = engine.decision(
            for: file("a.md"),
            preferredWindowID: nil,
            state: state
        )

        if case .openInSession(let w, _) = decision {
            XCTAssertEqual(w, blank)
        } else {
            XCTFail("expected .openInSession(blank), got \(decision)")
        }
    }

    func testCreatesWindowWhenNoBlankAvailable() {
        let occupied = WindowID()
        var state = WindowRoutingState()
        state.sessions[occupied] = SessionRoutingSnapshot(id: occupied, isBlank: false)

        let decision = engine.decision(
            for: file("a.md"),
            preferredWindowID: nil,
            state: state,
            makeWindowID: { WindowID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!) }
        )

        if case .createWindow = decision { return }
        XCTFail("expected .createWindow, got \(decision)")
    }
}
