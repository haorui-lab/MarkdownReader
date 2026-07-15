import XCTest
@testable import MarkdownReader

/// 文件所有权与目录树选择测试（Task 9 Step 1）。
///
/// 验证跨窗口所有权冲突场景（需求 §6.5）：目录窗口点击已被另一窗口持有的文件时，
/// 目录窗口保持当前有效选择不变、不加载该文档，并激活所有者窗口；所有者关闭后
/// 目录窗口才可选该文件。同时验证文件行的所有权标记。
@MainActor
final class FileOwnershipSelectionTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeSession(coordinator: WindowCoordinator) -> WindowSession {
        WindowSession(id: WindowID(), coordinator: coordinator)
    }

    // MARK: - 目录窗口选择被独立窗口持有的文件 → 激活 owner，不改选择

    func testDirectorySelectionActivatesStandaloneOwner() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let directory = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: directory)

        let aURL = try makeFile(named: "A.md", content: "# A")
        let identity = try identityService.identity(for: aURL, kind: .file)
        try coordinator.claim(identity, for: owner.id)

        // 目录窗口当前选择 B.md（有效选择）
        let bURL = try makeFile(named: "B.md", content: "# B")
        directory.fileTreeViewModel.selectedFileURL = bURL

        directory.requestFileSelection(aURL)

        XCTAssertEqual(directory.fileTreeViewModel.selectedFileURL, bURL,
                       "冲突时目录窗口选中项必须保持不变")
        XCTAssertEqual(coordinator.lastActiveWindowID, owner.id,
                       "冲突时必须激活所有者窗口")
    }

    // MARK: - 冲突时目录窗口选中项不变

    func testOwnerConflictKeepsDirectorySelectionUnchanged() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let directory = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: directory)

        let aURL = try makeFile(named: "A.md", content: "# A")
        try coordinator.claim(identityService.identity(for: aURL, kind: .file), for: owner.id)

        let previous = try makeFile(named: "B.md", content: "# B")
        directory.fileTreeViewModel.selectedFileURL = previous

        directory.requestFileSelection(aURL)

        XCTAssertEqual(directory.fileTreeViewModel.selectedFileURL, previous,
                       "所有者冲突时目录窗口选中项必须保持不变")
    }

    // MARK: - 冲突时不加载文档（DocumentViewModel.currentFileURL 不变）

    func testOwnerConflictDoesNotLoadDocument() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let directory = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: directory)

        let aURL = try makeFile(named: "A.md", content: "# A")
        try coordinator.claim(identityService.identity(for: aURL, kind: .file), for: owner.id)

        // 目录窗口未打开任何文档
        XCTAssertNil(directory.documentViewModel.currentFileURL)

        directory.requestFileSelection(aURL)

        XCTAssertNil(directory.documentViewModel.currentFileURL,
                     "冲突时不得加载文档到目录窗口，避免双所有权")
    }

    // MARK: - 所有者关闭后，目录窗口可选该文件

    func testClosingOwnerAllowsDirectoryWindowToSelectFile() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let directory = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: directory)

        let aURL = try makeFile(named: "A.md", content: "# A")
        try coordinator.claim(identityService.identity(for: aURL, kind: .file), for: owner.id)

        // owner 关闭：释放所有权 + 注销
        owner.dispose()

        // 现在目录窗口可选 A.md（路由返回 .openInSession）
        directory.requestFileSelection(aURL)
        XCTAssertEqual(directory.fileTreeViewModel.selectedFileURL, aURL,
                       "所有者关闭后目录窗口应能选中原冲突文件")
    }

    // MARK: - 文件行标记：被另一窗口持有的文件

    func testRowMarksFileOwnedByAnotherWindow() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let directory = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: directory)

        let aURL = try makeFile(named: "A.md", content: "# A")
        try coordinator.claim(identityService.identity(for: aURL, kind: .file), for: owner.id)

        // 从目录窗口视角，A.md 由另一窗口持有
        XCTAssertTrue(coordinator.isFileOwnedByAnotherWindow(aURL, besides: directory.id),
                      "目录窗口应能识别 A.md 由另一窗口持有")
        // 从 owner 自身视角，A.md 不算「另一窗口」
        XCTAssertFalse(coordinator.isFileOwnedByAnotherWindow(aURL, besides: owner.id),
                       "owner 自身不应标记自己的文件为另一窗口持有")
    }
}
