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
    }

    // MARK: - 回归修复：Cmd+N 释放此前真实文件所有权

    /// 复现路径：选 A → Cmd+N（空 Untitled）→ A 仍归本窗口 → 再选 A 无反应。
    /// 修复后 Cmd+N 成功创建 Untitled 时必须释放 A 的所有权，根目录所有权保留。
    func testCmdNReleasesPreviouslySelectedFileOwnership() throws {
        let coordinator = WindowCoordinator()
        let created = CreatedWindowsBox()
        coordinator.windowCreationClosureForTesting = { id in created.ids.append(id) }

        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        let dirIdentity = try identityService.identity(for: dir, kind: .directory)
        try coordinator.claim(dirIdentity, for: session.id)
        // 当前显示并持有 A.md
        session.documentViewModel.currentFileURL = a
        session.fileTreeViewModel.selectedFileURL = a
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)

        // Cmd+N：当前非脏，直接创建 Untitled
        session.handleNewFile()

        XCTAssertTrue(session.documentViewModel.isUntitled, "Cmd+N 后应为 Untitled 文档")
        XCTAssertNil(coordinator.owner(of: try identityService.identity(for: a, kind: .file)),
                     "Cmd+N 后必须释放此前 A.md 的所有权")
        XCTAssertEqual(coordinator.owner(of: dirIdentity), session.id,
                       "Cmd+N 后根目录所有权必须保留")
        XCTAssertNil(session.fileTreeViewModel.selectedFileURL, "Cmd+N 后选中项应清空")
        XCTAssertTrue(created.ids.isEmpty, "Cmd+N 不得创建新窗口")
    }

    // MARK: - 回归修复：干净 Untitled 可在 B 与 A 间往返切换

    /// 复现路径：选 A → Cmd+N（不修改）→ 选 B → 再选 A 无反应。
    /// 修复后应能正确切换到 A，B 所有权释放，A 重新归当前窗口，不创建新窗口。
    func testCleanUntitledCanSwitchBThenReturnToA() throws {
        let coordinator = WindowCoordinator()
        let created = CreatedWindowsBox()
        coordinator.windowCreationClosureForTesting = { id in created.ids.append(id) }

        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        try coordinator.claim(identityService.identity(for: dir, kind: .directory), for: session.id)
        session.documentViewModel.currentFileURL = a
        session.fileTreeViewModel.selectedFileURL = a
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)

        // Cmd+N：创建干净 Untitled（A 所有权被释放）
        session.handleNewFile()
        XCTAssertTrue(session.documentViewModel.isUntitled)

        // 选 B：可正常切换。此时 currentFileURL 仍是 Untitled 临时文件，
        // commitFileSwitchTransaction 经 oldSelectionURL（nil，Cmd+N 已清空）不释放 A；
        // A 在此前已被 Cmd+N 释放。
        session.requestFileSelection(b)
        XCTAssertEqual(session.fileTreeViewModel.selectedFileURL, b, "应能切换到 B.md")
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: b, kind: .file)), session.id,
                       "B.md 所有权应归当前窗口")

        // 再选 A：此前已被 Cmd+N 释放，应能再次切换（自愈）。
        // 此时 selectedFileURL=b，commitFileSwitchTransaction 经 oldSelectionURL 释放 B 所有权。
        session.requestFileSelection(a)
        XCTAssertEqual(session.fileTreeViewModel.selectedFileURL, a, "应能再次切换回 A.md")
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: a, kind: .file)), session.id,
                       "A.md 所有权应重新归当前窗口")
        XCTAssertNil(coordinator.owner(of: try identityService.identity(for: b, kind: .file)),
                     "切回 A 后 B.md 所有权应经 oldSelectionURL 释放")
        XCTAssertTrue(created.ids.isEmpty, "目录内导航不得创建新窗口")
    }

    // MARK: - 回归修复：本窗口持有但非当前文档不得视为幂等（自愈）

    /// 构造历史残留：A 归当前窗口持有，但当前实际显示 B，selectedFileURL 也是 B。
    /// 此时选择 A 不应被幂等判断吞掉，必须重新切换到 A。
    func testSelfOwnedButNotCurrentFileIsNotTreatedAsIdempotent() throws {
        let coordinator = WindowCoordinator()
        let dir = try makeDirectory(named: "docs")
        let a = try makeFile(named: "A.md", in: dir, content: "# A")
        let b = try makeFile(named: "B.md", in: dir, content: "# B")

        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)
        session.appViewModel.openDirectory(dir)
        try coordinator.claim(identityService.identity(for: dir, kind: .directory), for: session.id)

        // 残留状态：A 归本窗口持有，但当前文档/选中项都是 B
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: session.id)
        session.documentViewModel.currentFileURL = b
        session.fileTreeViewModel.selectedFileURL = b

        // 选择 A：虽「本窗口持有」，但非当前文档，应继续切换。
        // 此时 selectedFileURL=b，commitFileSwitchTransaction 经 oldSelectionURL 释放 B 所有权。
        session.requestFileSelection(a)

        XCTAssertEqual(session.fileTreeViewModel.selectedFileURL, a,
                       "持有但非当前文档时必须切换到 A，不得幂等吞掉")
        XCTAssertEqual(coordinator.owner(of: try identityService.identity(for: a, kind: .file)), session.id,
                       "A.md 所有权仍归当前窗口")
        XCTAssertNil(coordinator.owner(of: try identityService.identity(for: b, kind: .file)),
                     "切到 A 后 B.md 所有权应经 oldSelectionURL 释放")
    }
}

/// 记录测试中创建的 windowID，用于断言「未创建新窗口」。
@MainActor
final class CreatedWindowsBox {
    var ids: [WindowID] = []
}
