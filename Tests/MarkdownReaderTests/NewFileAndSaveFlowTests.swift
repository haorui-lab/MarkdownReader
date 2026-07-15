import XCTest
@testable import MarkdownReader

/// 回归修复 §三 + §一：新建/保存流程与命令分发隔离测试。
///
/// 使用 fake `UnsavedCloseInteraction` 避免在 headless 环境弹 AppKit 面板。
/// 覆盖：脏 Untitled 新建的三分支、Cmd+S 对 Untitled 进入 Save As、命令只作用于
/// 绑定 session（不串扰其他窗口）。
@MainActor
final class NewFileAndSaveFlowTests: TemporaryDirectoryTestCase {

    // MARK: - fake 交互边界

    final class FakeInteraction: UnsavedCloseInteraction {
        var promptChoice: UnsavedPromptChoice = .cancel
        var saveTarget: URL?

        func presentUnsavedChangesPrompt(for session: WindowSession) -> UnsavedPromptChoice {
            promptChoice
        }

        func chooseSaveAsTarget(
            for session: WindowSession,
            suggestedName: String,
            defaultDirectory: URL?
        ) async -> URL? {
            saveTarget
        }
    }

    private func makeSession(coordinator: WindowCoordinator, interaction: FakeInteraction) -> WindowSession {
        let session = WindowSession(id: WindowID(), coordinator: coordinator)
        // 把 fake 交互边界装进一个独立的终止协调器，供 handleNewFile 复用保存确认流程
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator, closeInteraction: interaction)
        session.terminationCoordinatorForTesting = termCoord
        // headless 测试不调真实 NSSavePanel（runModal 会阻塞），用 fake 选择器替代。
        session.savePanelChooserForTesting = { [weak interaction] _, _ in interaction?.saveTarget }
        return session
    }

    private func makeDirtyUntitled(coordinator: WindowCoordinator, interaction: FakeInteraction) -> WindowSession {
        let session = makeSession(coordinator: coordinator, interaction: interaction)
        session.documentViewModel.createUntitledFile()
        session.documentViewModel.content = "# dirty"
        session.appViewModel.hasUnsavedUntitled = true
        session.appViewModel.untitledFileName = session.documentViewModel.fileName
        return session
    }

    /// 等待 handleNewFile/handleSave 内部 Task 完成（保存确认 + 落盘均为异步）。
    private func waitForAsyncSessionWork() async {
        // handleNewFile/handleSave 启动 Task 后，内容落盘是真正的 async 文件 IO。
        // 用固定短 sleep 让出主 actor 并等待 IO 完成，避免无限 yield 空转。
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - Untitled 新建：不保存分支 → 清理旧 Untitled 后创建新 Untitled

    func testNewFileWithDirtyUntitledDontSaveCreatesNew() async throws {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let session = makeDirtyUntitled(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: session)
        interaction.promptChoice = .dontSave

        let oldUntitledURL = session.documentViewModel.currentFileURL
        session.handleNewFile()
        // handleNewFile 内部 await resolveUnsavedChanges，等待一个 runloop
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()

        XCTAssertFalse(session.documentViewModel.isUntitled == false && session.documentViewModel.content == "# dirty",
                       "不保存后旧脏内容不得保留")
        XCTAssertTrue(session.documentViewModel.isUntitled, "应创建新的 Untitled")
        XCTAssertEqual(session.documentViewModel.content, "", "新 Untitled 内容应为空，旧脏内容已丢弃")
        // 旧脏内容不得落盘（不保存分支不应写出文件）
        XCTAssertNil(oldUntitledURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0 == "# dirty" ? $0 : nil },
                     "不保存分支不得把旧脏内容落盘")
    }

    // MARK: - Untitled 新建：取消分支 → 保持当前内容和窗口不变

    func testNewFileWithDirtyUntitledCancelKeepsContent() async {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let session = makeDirtyUntitled(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: session)
        interaction.promptChoice = .cancel

        session.handleNewFile()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()

        XCTAssertEqual(session.documentViewModel.content, "# dirty", "取消后内容必须保持不变")
        XCTAssertTrue(session.documentViewModel.isUntitled, "取消后仍是原 Untitled")
    }

    // MARK: - Untitled 新建：保存成功分支 → 创建新 Untitled

    func testNewFileWithDirtyUntitledSaveCreatesNew() async throws {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let session = makeDirtyUntitled(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: session)
        let saveURL = try makeFile(named: "saved.md", content: "")
        interaction.promptChoice = .save
        interaction.saveTarget = saveURL

        session.handleNewFile()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()

        XCTAssertTrue(session.documentViewModel.isUntitled, "保存成功后应创建新 Untitled")
        XCTAssertFalse(session.documentViewModel.content == "# dirty", "新 Untitled 内容非旧脏内容")
        // 旧内容已落盘
        let written = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(written, "# dirty")
    }

    // MARK: - Cmd+S 对 Untitled 进入 Save As（不静默 no-op）

    func testSaveOnUntitledEntersSaveAs() async throws {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let session = makeDirtyUntitled(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: session)
        let saveURL = try makeFile(named: "saveas.md", content: "")
        interaction.saveTarget = saveURL

        // DocumentViewModel.save() 对 Untitled 返回 false；handleSave 应转 handleSaveAs。
        session.handleSave()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()

        // Save As 成功后 isUntitled 应被清除，内容落盘
        XCTAssertFalse(session.documentViewModel.isUntitled, "Untitled 经 Save As 后应清除 isUntitled")
        let written = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(written, "# dirty", "Save As 应把内容落盘")
    }

    // MARK: - 命令分发隔离：对 A 的 target 发命令不影响 B

    func testCommandTargetsOnlyOwningSession() {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let a = makeSession(coordinator: coordinator, interaction: interaction)
        let b = makeSession(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: a)
        coordinator.register(session: b)

        // a 打开 sidebar，b 保持关闭
        a.appViewModel.isSidebarVisible = true
        b.appViewModel.isSidebarVisible = false

        // 对 a 的 target 发 toggleSidebar
        a.commandTarget.perform(.toggleSidebar)

        // a 的 sidebar 翻转，b 不受影响
        XCTAssertFalse(a.appViewModel.isSidebarVisible, "a 的 sidebar 应被翻转")
        XCTAssertFalse(b.appViewModel.isSidebarVisible, "b 不应被 a 的命令触及")
    }

    // MARK: - 普通文件 Cmd+S 直接保存（不走 Save As）

    func testSaveOnRegularFileSavesDirectly() async throws {
        let coordinator = WindowCoordinator()
        let interaction = FakeInteraction()
        let session = makeSession(coordinator: coordinator, interaction: interaction)
        coordinator.register(session: session)

        let url = try makeFile(named: "regular.md", content: "# original")
        try coordinator.claim(try ResourceIdentityService().identity(for: url, kind: .file), for: session.id)
        await session.documentViewModel.loadFile(at: url)
        session.documentViewModel.content = "# changed"

        session.handleSave()
        await waitForAsyncSessionWork()
        await waitForAsyncSessionWork()

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(written, "# changed", "普通文件应直接保存到原路径")
    }
}
