import XCTest
@testable import MarkdownReader

/// WindowSession 行为测试。
///
/// Task 5 Step 1 的失败测试：验证 session 初始为空白、ViewModel 间依赖连接、
/// 关闭只清理本窗口状态、所有者冲突不改选中项。
@MainActor
final class WindowSessionTests: TemporaryDirectoryTestCase {

    private func makeSession(coordinator: WindowCoordinator? = nil) -> WindowSession {
        WindowSession(id: WindowID(), coordinator: coordinator)
    }

    // MARK: - 初始空白

    func testSessionStartsBlank() {
        let session = makeSession()
        XCTAssertTrue(session.isBlank, "新建 session 必须初始为空白窗口")
    }

    // MARK: - ViewModel 连接

    func testSessionWiresFileTreeToDocumentViewModel() {
        let session = makeSession()
        // WindowSession.init 应把 fileTreeViewModel.documentViewModel 接到本会话的 documentViewModel
        XCTAssertNotNil(session.fileTreeViewModel.documentViewModel)
        XCTAssertTrue(session.fileTreeViewModel.documentViewModel === session.documentViewModel,
                      "文件树 VM 必须指向本会话的文档 VM，避免跨窗口串扰")
    }

    func testSessionWiresCommandPaletteDependencies() {
        let session = makeSession()
        // 命令面板 VM 的依赖应全部指向本会话对象
        XCTAssertNotNil(session.commandPaletteViewModel.appViewModel)
        XCTAssertTrue(session.commandPaletteViewModel.appViewModel === session.appViewModel)
        XCTAssertTrue(session.commandPaletteViewModel.documentViewModel === session.documentViewModel)
    }

    // MARK: - dispose 只清理本窗口

    func testDisposeUnregistersOnlyItsOwnSession() {
        let coordinator = WindowCoordinator()
        let a = WindowSession(id: WindowID(), coordinator: coordinator)
        let b = WindowSession(id: WindowID(), coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)
        XCTAssertTrue(coordinator.isRegistered(a.id))
        XCTAssertTrue(coordinator.isRegistered(b.id))

        a.dispose()

        XCTAssertFalse(coordinator.isRegistered(a.id), "dispose 后本窗口必须注销")
        XCTAssertTrue(coordinator.isRegistered(b.id), "dispose 不得影响其他窗口注册")
    }

    // MARK: - 所有者冲突不改选中项

    func testOwnerConflictLeavesSelectionUnchanged() throws {
        let coordinator = WindowCoordinator()
        let owner = WindowSession(id: WindowID(), coordinator: coordinator)
        let browser = WindowSession(id: WindowID(), coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: browser)

        let url = try makeFile(named: "A.md", content: "# A")
        let identity = try ResourceIdentityService().identity(for: url, kind: .file)
        try coordinator.claim(identity, for: owner.id)

        // browser 已有一个有效选中项（模拟目录窗口正在看 B.md）
        let currentSelection = try makeFile(named: "B.md", content: "# B")
        browser.fileTreeViewModel.selectedFileURL = currentSelection

        browser.requestFileSelection(url)

        // 关键约束（需求 §6.5）：冲突时目录窗口保持当前有效选择不变，激活 owner。
        XCTAssertEqual(browser.fileTreeViewModel.selectedFileURL, currentSelection,
                       "所有者冲突时目录窗口选中项必须保持不变，不得抢先加载 A.md")
    }

    // MARK: - 显式 isBlank flag（发现 3：消除派生竞态）

    func testExplicitBlankFlagSuppressedDuringOpen() {
        let session = makeSession()
        XCTAssertTrue(session.isBlank)
        // open 开始即置 false，即使 ViewModel 状态尚未异步刷新
        session.markOpenStarted()
        XCTAssertFalse(session.isBlank, "open 开始后必须立即视为非空白，避免路由误判复用")
    }

    func testExplicitBlankFlagRestoredOnFailedOpen() {
        let session = makeSession()
        session.markOpenStarted()
        XCTAssertFalse(session.isBlank)
        // open 失败应恢复空白标记，使该窗口仍可被复用
        session.markOpenFailed()
        XCTAssertTrue(session.isBlank, "open 失败后必须恢复空白，允许后续复用")
    }
}
