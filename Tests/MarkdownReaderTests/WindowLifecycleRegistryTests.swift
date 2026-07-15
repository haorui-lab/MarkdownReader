import XCTest
@testable import MarkdownReader

/// 窗口生命周期注册测试（Task 6 Step 1）。
///
/// 验证 WindowCoordinator 在窗口创建/关闭时的会话注册行为：注册使 session 可查询、
/// 关闭注销并释放所有权、同一 windowID 不会重复注册。这些是 data-driven WindowGroup
/// 生命周期桥接的核心不变式。
@MainActor
final class WindowLifecycleRegistryTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeCoordinator() -> WindowCoordinator {
        WindowCoordinator(identityService: identityService)
    }

    private func makeSession(id: WindowID, coordinator: WindowCoordinator) -> WindowSession {
        WindowSession(id: id, coordinator: coordinator)
    }

    // MARK: - 注册使 session 可用

    func testRegisterMakesSessionAvailable() {
        let coordinator = makeCoordinator()
        let id = WindowID()
        let session = makeSession(id: id, coordinator: coordinator)

        coordinator.register(session: session)

        XCTAssertTrue(coordinator.isRegistered(id), "注册后该 windowID 必须可见")
        XCTAssertTrue(coordinator.sessions[id] === session, "注册必须强持有同一 session 对象")
        XCTAssertEqual(coordinator.sessionCount, 1)
    }

    // MARK: - 关闭注销并释放所有权

    func testWindowCloseUnregistersAndReleasesResources() throws {
        let coordinator = makeCoordinator()
        let id = WindowID()
        let session = makeSession(id: id, coordinator: coordinator)
        coordinator.register(session: session)

        // 声明一个文件所有权
        let fileURL = try makeFile(named: "owned.md", content: "x")
        let resource = try identityService.identity(for: fileURL, kind: .file)
        XCTAssertNoThrow(try coordinator.claim(resource, for: id))
        XCTAssertEqual(coordinator.owner(of: resource), id)

        // 关闭窗口：注销 + 释放该窗口全部所有权
        session.dispose()

        XCTAssertFalse(coordinator.isRegistered(id), "dispose 后该 windowID 必须不可见")
        XCTAssertNil(coordinator.sessions[id], "dispose 后 session 必须被释放")
        XCTAssertNil(coordinator.owner(of: resource), "dispose 后资源所有权必须释放")
    }

    // MARK: - 同一 windowID 不重复注册

    func testSameWindowIDIsNotRegisteredTwice() {
        let coordinator = makeCoordinator()
        let id = WindowID()
        let first = makeSession(id: id, coordinator: coordinator)
        coordinator.register(session: first)

        // 用同一 id 再注册一个 session：注册表只保留一个，计数仍为 1
        let second = makeSession(id: id, coordinator: coordinator)
        coordinator.register(session: second)

        XCTAssertEqual(coordinator.sessionCount, 1, "同一 windowID 重复注册不得增加计数")
        XCTAssertTrue(coordinator.sessions[id] === second, "重复注册应以最新 session 覆盖")
    }

    // MARK: - dispose 幂等（Task 3）

    func testDisposeIsIdempotent() throws {
        let coordinator = makeCoordinator()
        let id = WindowID()
        let session = makeSession(id: id, coordinator: coordinator)
        coordinator.register(session: session)

        let fileURL = try makeFile(named: "owned.md", content: "x")
        let resource = try identityService.identity(for: fileURL, kind: .file)
        try coordinator.claim(resource, for: id)

        // 首次 dispose：注销 + 释放所有权
        session.dispose()
        XCTAssertFalse(coordinator.isRegistered(id))
        XCTAssertNil(coordinator.owner(of: resource))

        // 第二次 dispose：幂等，不 crash、不改变状态
        session.dispose()
        XCTAssertFalse(coordinator.isRegistered(id))
        XCTAssertNil(coordinator.owner(of: resource))
    }

    // MARK: - dispose 后资源立即可被其他窗口 claim（Task 3）

    func testResourceReclaimableAfterOwnerDispose() throws {
        let coordinator = makeCoordinator()
        let ownerID = WindowID()
        let otherID = WindowID()
        let owner = makeSession(id: ownerID, coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.registerSession(id: otherID, isBlank: true)

        let fileURL = try makeFile(named: "shared.md", content: "x")
        let resource = try identityService.identity(for: fileURL, kind: .file)
        try coordinator.claim(resource, for: ownerID)
        XCTAssertEqual(coordinator.owner(of: resource), ownerID)

        // owner dispose 同步释放所有权
        owner.dispose()
        XCTAssertNil(coordinator.owner(of: resource), "owner dispose 后资源应立即可被认领")

        // other 现在可以 claim 同一资源（无冲突）
        XCTAssertNoThrow(try coordinator.claim(resource, for: otherID),
                         "关闭 owner 后资源必须立即可被其他窗口 claim")
        XCTAssertEqual(coordinator.owner(of: resource), otherID)
    }

    // MARK: - dispose 同步完成：下一次路由快照不含已关闭窗口（Task 3）

    func testDisposedWindowAbsentFromRoutingSnapshot() throws {
        let coordinator = makeCoordinator()
        let closingID = WindowID()
        let survivingID = WindowID()
        let closing = makeSession(id: closingID, coordinator: coordinator)
        coordinator.register(session: closing)
        coordinator.registerSession(id: survivingID, isBlank: true)

        // 关闭中的窗口曾持有一个资源
        let fileURL = try makeFile(named: "closing-owned.md", content: "x")
        let resource = try identityService.identity(for: fileURL, kind: .file)
        try coordinator.claim(resource, for: closingID)

        // 同步 dispose
        closing.dispose()

        // 下一次路由快照不应含 closingID，且资源所有权已释放
        let snapshot = coordinator.routingSnapshot()
        XCTAssertNil(snapshot.sessions[closingID], "dispose 后路由快照不得含已关闭窗口")
        XCTAssertNil(snapshot.owners[resource], "dispose 后路由快照不得含已释放资源")
        XCTAssertNotNil(snapshot.sessions[survivingID], "存活窗口应仍在快照中")
    }
}
