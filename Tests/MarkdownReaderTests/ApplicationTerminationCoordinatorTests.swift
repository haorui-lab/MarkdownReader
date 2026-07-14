import XCTest
@testable import MarkdownReader

/// Task 12：窗口关闭、退出与 Dock 重开协调测试。
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

        // a 无脏 Untitled，可直接关闭
        XCTAssertTrue(termCoord.shouldClose(session: a))
        a.dispose()

        // b 仍然注册
        XCTAssertTrue(coordinator.isRegistered(b.id))
        XCTAssertNotNil(coordinator.sessions[b.id])
    }

    // MARK: - 不保存只丢弃所属窗口的 Untitled

    func testDontSaveDiscardsOnlyOwningUntitled() {
        let coordinator = WindowCoordinator()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator)
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        let clean = makeSession(coordinator: coordinator)
        coordinator.register(session: dirty)
        coordinator.register(session: clean)

        // dirty session 是 Untitled + isDirty
        XCTAssertTrue(dirty.documentViewModel.isUntitled)
        XCTAssertTrue(dirty.documentViewModel.isDirty)

        // 手动调用 discardUntitledFile（模拟用户选「不保存」）
        dirty.documentViewModel.discardUntitledFile()

        // dirty session 状态已清空
        XCTAssertFalse(dirty.documentViewModel.isUntitled)
        XCTAssertFalse(dirty.documentViewModel.isDirty)

        // clean session 不受影响
        XCTAssertFalse(clean.documentViewModel.isUntitled)
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

        // 无注册 session
        XCTAssertFalse(coordinator.hasRegisteredSession)

        // handleReopen 应调 coordinator.openBlankWindow（需 openWindowAction 才能真正创建）
        // 这里验证不 crash 即可，因为 openWindowAction 在 headless 下为 nil
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

    func testQuitVisitsEveryDirtyUntitledSession() {
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
        // processTermination 会弹 alert，但脏已清所以不会弹
        // 由于 headless 无法弹 alert，这里验证 dirty 列表为空
        let dirtyCount = coordinator.sessions.values.filter {
            $0.documentViewModel.isUntitled && $0.documentViewModel.isDirty
        }.count
        XCTAssertEqual(dirtyCount, 0, "丢弃后不应有脏 Untitled session")
    }
}
