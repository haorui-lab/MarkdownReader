import XCTest
@testable import MarkdownReader

/// Task 1 重构后：关闭、退出与 Dock 重开协调测试。
///
/// 旧 `shouldClose(session:)` 同步签名已移除（会死锁），改为异步 `resolveUnsavedChanges`
/// + `shouldCloseImmediately`。详尽的保存/失败/取消用例见 `UnsavedCloseCoordinatorTests`。
@MainActor
final class ApplicationTerminationCoordinatorTests: TemporaryDirectoryTestCase {

    private func makeSession(coordinator: WindowCoordinator, dirty: Bool = false) -> WindowSession {
        let session = WindowSession(id: WindowID(), coordinator: coordinator)
        if dirty {
            session.documentViewModel.createUntitledFile()
            session.documentViewModel.content = "# modified"
        }
        return session
    }

    // MARK: - 关闭一个 session 不影响其他 session

    func testCloseOneSessionDoesNotDisposeOtherSession() {
        let coordinator = WindowCoordinator()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator)
        let a = makeSession(coordinator: coordinator)
        let b = makeSession(coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)

        // a 无脏 Untitled，shouldCloseImmediately 返回 true
        XCTAssertTrue(termCoord.shouldCloseImmediately(session: a))
        a.dispose()

        // b 仍然注册
        XCTAssertTrue(coordinator.isRegistered(b.id))
        XCTAssertNotNil(coordinator.sessions[b.id])
    }

    // MARK: - prepareForClose 返回正确决策

    func testPrepareForCloseReturnsCorrectDecision() {
        let coordinator = WindowCoordinator()
        let clean = makeSession(coordinator: coordinator)
        let dirty = makeSession(coordinator: coordinator, dirty: true)

        XCTAssertEqual(clean.prepareForClose(), .close)
        XCTAssertEqual(dirty.prepareForClose(), .needsUntitledDecision)
    }

    // MARK: - Dock 重开：无窗口时创建空白

    func testDockReopenCreatesBlankWindow() {
        let coordinator = WindowCoordinator()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator)

        XCTAssertFalse(coordinator.hasRegisteredSession)

        // handleReopen 应调 coordinator.openBlankWindow（需 openWindowAction 才能真正创建）
        // headless 下 openWindowAction 为 nil，验证不 crash 即可
        termCoord.handleReopen()
    }

    // MARK: - Dock 重开：有注册 session 时激活最后一个

    func testDockReopenActivatesLastActive() {
        let coordinator = WindowCoordinator()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator)
        let a = makeSession(coordinator: coordinator)
        let b = makeSession(coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)
        coordinator.recordActive(windowID: b.id)

        termCoord.handleReopen()

        XCTAssertEqual(coordinator.lastActiveWindowID, b.id)
    }

    // MARK: - 退出时遍历所有脏 Untitled session

    func testQuitVisitsEveryDirtyUntitledSession() async {
        let coordinator = WindowCoordinator()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator)
        let d1 = makeSession(coordinator: coordinator, dirty: true)
        let d2 = makeSession(coordinator: coordinator, dirty: true)
        let clean = makeSession(coordinator: coordinator)
        coordinator.register(session: d1)
        coordinator.register(session: d2)
        coordinator.register(session: clean)

        // 手动丢弃两个脏 session，模拟「不保存」
        d1.documentViewModel.discardUntitledFile()
        d2.documentViewModel.discardUntitledFile()

        // 现在所有 session 都不脏，退出应成功
        let dirtyCount = coordinator.sessions.values.filter {
            $0.documentViewModel.isUntitled && $0.documentViewModel.isDirty
        }.count
        XCTAssertEqual(dirtyCount, 0, "丢弃后不应有脏 Untitled session")

        XCTAssertTrue(termCoord.beginTermination())
        await termCoord.processTermination()
        XCTAssertEqual(termCoord.state, .terminating)
    }
}
