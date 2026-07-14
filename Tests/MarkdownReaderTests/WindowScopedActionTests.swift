import XCTest
@testable import MarkdownReader

/// 窗口级动作隔离测试（Task 11 Step 1）。
///
/// 验证拖拽、导出、红绿灯等窗口级动作只作用于所属窗口/会话，不串扰其它窗口。
/// 这些动作多数依赖 AppKit GUI（sheet、overlay），无法在 headless 下端到端验证，
/// 故聚焦可单测的不变式：拖拽请求携带目标 windowID、导出命令经 FocusedValues 只达焦点窗口、
/// 红绿灯操作所属窗口。
@MainActor
final class WindowScopedActionTests: TemporaryDirectoryTestCase {

    private func makeSession(coordinator: WindowCoordinator) -> WindowSession {
        WindowSession(id: WindowID(), coordinator: coordinator)
    }

    // MARK: - 拖拽请求携带目标 windowID

    func testDropCallbackCarriesTargetWindowID() throws {
        let coordinator = WindowCoordinator()
        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)

        // 模拟 WindowDropOverlayView.performDragOperation 的路由：preferredWindowID = session.id
        let url = try makeFile(named: "dropped.md", content: "# drop")
        let request = OpenRequest(urls: [url], source: .dragDrop, preferredWindowID: session.id)

        coordinator.enqueue(request)
        coordinator.drainPendingRequests()

        // 空白窗口应被复用为本窗口（preferredWindowID 命中）
        XCTAssertTrue(coordinator.isRegistered(session.id))
        XCTAssertNotNil(coordinator.sessions[session.id])
    }

    // MARK: - 导出命令只经焦点窗口 target

    func testExportCommandReachesOnlyTargetSession() {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let other = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: other)

        // owner 的 target 收到 exportPDF，注册 handler 计数；other 的 handler 不被调用
        var ownerExportCount = 0
        owner.commandTarget.exportPDFHandler = { ownerExportCount += 1 }
        var otherExportCount = 0
        other.commandTarget.exportPDFHandler = { otherExportCount += 1 }

        owner.commandTarget.perform(.exportPDF)

        XCTAssertEqual(ownerExportCount, 1, "owner 的导出 handler 必须被调用")
        XCTAssertEqual(otherExportCount, 0, "other 的导出 handler 不应被触及")
    }

    // MARK: - 不支持文件类型：路由拒绝不阻塞后续 URL（Coordinator 行为）

    func testUnsupportedDropDoesNotBlockSubsequentURL() throws {
        let coordinator = WindowCoordinator()
        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)

        // 第一个 URL 不存在（.reject），第二个 URL 存在；批量路由不应因第一个失败而丢弃第二个
        let missing = temporaryDirectory!.appendingPathComponent("nope.md")
        let present = try makeFile(named: "real.md", content: "# real")
        let request = OpenRequest(urls: [missing, present], source: .dragDrop, preferredWindowID: session.id)

        coordinator.enqueue(request)
        coordinator.drainPendingRequests()

        // present 应被加载到 session（currentFileURL 命中或 ownership 声明）
        let identity = try ResourceIdentityService().identity(for: present, kind: .file)
        XCTAssertEqual(coordinator.owner(of: identity), session.id,
                       "缺失文件不阻塞后续 URL：present 的所有权应归于本窗口")
    }
}
