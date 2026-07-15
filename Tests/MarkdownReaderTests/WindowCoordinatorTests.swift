import XCTest
@testable import MarkdownReader

/// WindowCoordinator 注册表与所有权事务测试。
///
/// 这些测试只覆盖 Coordinator 的注册表与所有权逻辑，不依赖真实 NSWindow。
/// session 通过最小 stub 注入。Coordinator 是 @MainActor，测试类同步标注。
@MainActor
final class WindowCoordinatorTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeCoordinator() -> WindowCoordinator {
        WindowCoordinator(identityService: identityService)
    }

    private func file(_ name: String) -> ResourceIdentity {
        let url = (try? makeFile(named: name, content: "x")) ?? temporaryDirectory!.appendingPathComponent(name)
        return try! identityService.identity(for: url, kind: .file)
    }

    private func fileURL(_ name: String) -> URL {
        (try? makeFile(named: name, content: "x")) ?? temporaryDirectory!.appendingPathComponent(name)
    }

    // MARK: - 注册/注销

    func testRegisterAndUnregisterSession() {
        let coordinator = makeCoordinator()
        let id = WindowID()
        coordinator.registerSession(id: id, isBlank: true)

        XCTAssertTrue(coordinator.isRegistered(id))
        XCTAssertEqual(coordinator.sessionCount, 1)

        coordinator.unregister(windowID: id)
        XCTAssertFalse(coordinator.isRegistered(id))
        XCTAssertEqual(coordinator.sessionCount, 0)
    }

    // MARK: - 所有权

    func testClaimRejectsSecondOwner() {
        let coordinator = makeCoordinator()
        let a = WindowID()
        let b = WindowID()
        let resource = file("a.md")
        coordinator.registerSession(id: a, isBlank: false)
        coordinator.registerSession(id: b, isBlank: false)

        XCTAssertNoThrow(try coordinator.claim(resource, for: a))
        XCTAssertEqual(coordinator.owner(of: resource), a)

        // 第二个窗口不能再 claim 同一资源
        XCTAssertThrowsError(try coordinator.claim(resource, for: b))
        XCTAssertEqual(coordinator.owner(of: resource), a, "所有权应保持原 owner")
    }

    func testUnregisterReleasesAllOwnedResources() {
        let coordinator = makeCoordinator()
        let a = WindowID()
        coordinator.registerSession(id: a, isBlank: false)

        let r1 = file("a.md")
        let r2 = file("b.md")
        try? coordinator.claim(r1, for: a)
        try? coordinator.claim(r2, for: a)
        XCTAssertEqual(coordinator.owner(of: r1), a)
        XCTAssertEqual(coordinator.owner(of: r2), a)

        coordinator.unregister(windowID: a)
        XCTAssertNil(coordinator.owner(of: r1))
        XCTAssertNil(coordinator.owner(of: r2))
    }

    // MARK: - 迁移事务

    func testMigrationMovesOwnershipAtomically() throws {
        let coordinator = makeCoordinator()
        let a = WindowID()
        coordinator.registerSession(id: a, isBlank: false)

        let oldURL = fileURL("old.md")
        let newURL = fileURL("new.md")
        let oldID = try identityService.identity(for: oldURL, kind: .file)
        let newID = try identityService.identity(for: newURL, kind: .file)

        try coordinator.claim(oldID, for: a)
        try coordinator.migrateOwnership(from: oldURL, to: newURL, for: a)

        XCTAssertEqual(coordinator.owner(of: newID), a)
        XCTAssertNil(coordinator.owner(of: oldID))
    }

    func testMigrationConflictPreservesOldOwnership() throws {
        let coordinator = makeCoordinator()
        let a = WindowID()
        let b = WindowID()
        coordinator.registerSession(id: a, isBlank: false)
        coordinator.registerSession(id: b, isBlank: false)

        let sourceURL = fileURL("source.md")
        let occupiedURL = fileURL("occupied.md")
        let sourceID = try identityService.identity(for: sourceURL, kind: .file)
        let occupiedID = try identityService.identity(for: occupiedURL, kind: .file)

        try coordinator.claim(sourceID, for: a)
        try coordinator.claim(occupiedID, for: b)

        // 迁移到已被 b 持有的目标应失败，且 a 的旧所有权保持不变。
        XCTAssertThrowsError(try coordinator.migrateOwnership(from: sourceURL, to: occupiedURL, for: a))
        XCTAssertEqual(coordinator.owner(of: sourceID), a)
        XCTAssertEqual(coordinator.owner(of: occupiedID), b)
    }

    // MARK: - pending resource

    func testPendingRequestIsStoredByDestinationWindowID() {
        let coordinator = makeCoordinator()
        let id = WindowID()
        let resource = file("pending.md")

        coordinator.storePending(resource: resource, for: id)
        let consumed = coordinator.consumePendingResource(for: id)
        XCTAssertEqual(consumed, resource)

        // 消费一次后清空
        XCTAssertNil(coordinator.consumePendingResource(for: id))
    }

    // MARK: - 路由集成

    func testRouteFileSelectionActivatesOwner() throws {
        let coordinator = makeCoordinator()
        let owner = WindowID()
        let other = WindowID()
        coordinator.registerSession(id: owner, isBlank: false)
        coordinator.registerSession(id: other, isBlank: true)

        let url = fileURL("owned.md")
        let identity = try identityService.identity(for: url, kind: .file)
        try coordinator.claim(identity, for: owner)

        let decision = coordinator.routeFileSelection(url, from: other)
        if case .activateOwner(let windowID, _) = decision {
            XCTAssertEqual(windowID, owner)
        } else {
            XCTFail("expected .activateOwner, got \(decision)")
        }
    }

    func testRouteFileSelectionOpensInBlankSession() {
        let coordinator = makeCoordinator()
        let blank = WindowID()
        coordinator.registerSession(id: blank, isBlank: true)

        let url = fileURL("free.md")
        let decision = coordinator.routeFileSelection(url, from: blank)
        if case .openInSession(let windowID, _) = decision {
            XCTAssertEqual(windowID, blank)
        } else {
            XCTFail("expected .openInSession, got \(decision)")
        }
    }
}
