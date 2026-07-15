import XCTest
@testable import MarkdownReader

/// 回归修复 §二：目录窗口专用文件切换事务测试。
///
/// 验证目录树/命令面板选择当前根目录内文件时不进入通用外部打开路由：
/// - 无 owner → 在当前目录窗口打开，不创建新窗口，并声明所有权；
/// - 有其他 owner → 保持当前选中项与文档不变，激活 owner；
/// - 已持有 → 幂等；
/// - A.md → B.md 切换后，B 归当前窗口，A 可被其他窗口重新打开。
@MainActor
final class DirectoryWindowNavigationTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeSession(coordinator: WindowCoordinator) -> WindowSession {
        WindowSession(id: WindowID(), coordinator: coordinator)
    }

    // MARK: - 无 owner：在当前目录窗口打开，不创建新窗口

    func testUnownedFileOpensInCurrentDirectoryWindow() throws {
        let coordinator = WindowCoordinator()
        let created = CreatedWindowsBox()
        coordinator.windowCreationClosureForTesting = { id in created.ids.append(id) }

        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        // 模拟已承载根目录的目录窗口（非空白）
        session.appViewModel.openDirectory(dir)
        try coordinator.claim(identityService.identity(for: dir, kind: .directory), for: session.id)
        // 当前显示 A.md 并持有其所有权
        session.documentViewModel.currentFileURL = a
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)
        session.fileTreeViewModel.selectedFileURL = a

        // 点击 B.md（无其他 owner）
        session.requestFileSelection(b)

        XCTAssertEqual(session.fileTreeViewModel.selectedFileURL, b, "应在当前窗口切换到 B.md")
        XCTAssertTrue(created.ids.isEmpty, "目录内导航不得创建新窗口")
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: b, kind: .file)), session.id,
                       "B.md 所有权应归属当前目录窗口")
    }

    // MARK: - 切换后旧文件所有权释放，可被其他窗口重新打开

    func testSwitchingFilesReleasesOldFileOwnership() throws {
        let coordinator = WindowCoordinator()
        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        try coordinator.claim(identityService.identity(for: dir, kind: .directory), for: session.id)
        session.documentViewModel.currentFileURL = a
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)

        // A.md → B.md
        session.requestFileSelection(b)

        XCTAssertNil(coordinator.owner(of: try identityService.identity(for: a, kind: .file)),
                     "切换后旧文件 A.md 所有权应释放")
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: b, kind: .file)), session.id,
                       "B.md 所有权应归属当前窗口")

        // 另一窗口现在可以打开 A.md
        let other = makeSession(coordinator: coordinator)
        coordinator.register(session: other)
        XCTAssertFalse(coordinator.isFileOwnedByAnotherWindow(a, besides: other.id),
                       "A.md 释放后其他窗口应能打开")
    }

    // MARK: - 有其他 owner：保持当前选中项与文档不变，激活 owner

    func testOwnedFileActivatesOwnerWithoutChangingSelection() throws {
        let coordinator = WindowCoordinator()
        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let owner = makeSession(coordinator: coordinator)
        let browser = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: browser)

        // owner 持有 A.md
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: owner.id)

        // browser 当前显示 B.md
        browser.appViewModel.openDirectory(dir)
        browser.documentViewModel.currentFileURL = b
        browser.fileTreeViewModel.selectedFileURL = b

        // browser 点击 A.md（已被 owner 持有）
        browser.requestFileSelection(a)

        XCTAssertEqual(browser.fileTreeViewModel.selectedFileURL, b, "冲突时目录窗口选中项必须保持不变")
        XCTAssertEqual(browser.documentViewModel.currentFileURL, b, "冲突时不得加载文档到目录窗口")
        XCTAssertEqual(coordinator.lastActiveWindowID, owner.id, "冲突时必须激活所有者窗口")
    }

    // MARK: - 已持有该文件：幂等

    func testAlreadyOwnedFileIsIdempotent() throws {
        let coordinator = WindowCoordinator()
        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        session.documentViewModel.currentFileURL = a
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)
        session.fileTreeViewModel.selectedFileURL = a

        let selectionBefore = session.fileTreeViewModel.selectedFileURL
        // 再次点击同一文件：幂等，不重复加载/不改状态
        session.requestFileSelection(a)
        XCTAssertEqual(session.fileTreeViewModel.selectedFileURL, selectionBefore)
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: a, kind: .file)), session.id)
    }

    // MARK: - 根目录所有权在切换文件后保留

    func testRootDirectoryOwnershipRetainedAfterFileSwitch() throws {
        let coordinator = WindowCoordinator()
        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        let dirIdentity = try identityService.identity(for: dir, kind: .directory)
        try coordinator.claim(dirIdentity, for: session.id)
        session.documentViewModel.currentFileURL = a
        try coordinator.claim(try identityService.identity(for: a, kind: .file), for: session.id)

        session.requestFileSelection(b)

        XCTAssertEqual(coordinator.owner(of: dirIdentity), session.id,
                       "切换文件后根目录所有权必须保留")
    }}

/// 记录测试中创建的 windowID，用于断言「未创建新窗口」。
@MainActor
final class CreatedWindowsBox {
    var ids: [WindowID] = []
}
