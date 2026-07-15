import XCTest
@testable import MarkdownReader

/// Task 1：关闭 / 退出状态机测试。
///
/// 注入 fake 交互边界（`FakeUnsavedCloseInteraction`），避免 headless 环境弹 `NSAlert` / `NSSavePanel`。
/// 覆盖：保存成功才允许关闭、保存失败保持打开、取消面板保持打开、不保存只清所属 session、
/// 重复 Cmd+W 单流程、多脏窗口串行退出、任一失败终止退出、重复 Cmd+Q 不重复 reply。
@MainActor
final class UnsavedCloseCoordinatorTests: TemporaryDirectoryTestCase {

    // MARK: - fake 交互边界

    /// 可编程的未保存交互边界。
    /// 通过 `promptChoice` 控制用户选择，通过 `saveTarget` 控制保存面板返回（nil 表示取消面板）。
    final class FakeUnsavedCloseInteraction: UnsavedCloseInteraction {
        var promptChoice: UnsavedPromptChoice = .cancel
        /// 保存面板返回的目标 URL；nil 表示用户取消面板。
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

    private func makeSession(coordinator: WindowCoordinator, dirty: Bool = false) -> WindowSession {
        let session = WindowSession(id: WindowID(), coordinator: coordinator)
        if dirty {
            session.documentViewModel.createUntitledFile()
            session.documentViewModel.content = "# modified"
            // 镜像 WindowSession.handleNewFile 的完整副作用，使 hasUnsavedUntitled 与 Untitled 状态一致
            session.appViewModel.hasUnsavedUntitled = true
            session.appViewModel.untitledFileName = session.documentViewModel.fileName
        }
        return session
    }

    private func makeCoordinatorAndInteraction() -> (WindowCoordinator, ApplicationTerminationCoordinator, FakeUnsavedCloseInteraction) {
        let coordinator = WindowCoordinator()
        let interaction = FakeUnsavedCloseInteraction()
        let termCoord = ApplicationTerminationCoordinator(coordinator: coordinator, closeInteraction: interaction)
        return (coordinator, termCoord, interaction)
    }

    // MARK: - 保存成功后才允许关闭

    func testSaveSuccessAllowsClose() async throws {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: dirty)

        let saveURL = try makeFile(named: "saved.md", content: "")
        interaction.promptChoice = .save
        interaction.saveTarget = saveURL

        let decision = await termCoord.resolveUnsavedChanges(for: dirty)

        XCTAssertEqual(decision, .proceed, "保存成功应返回 proceed")
        XCTAssertFalse(dirty.documentViewModel.isUntitled, "保存后 isUntitled 必须清除")
        XCTAssertFalse(dirty.documentViewModel.isDirty, "保存后 isDirty 必须清除")
        XCTAssertFalse(dirty.appViewModel.hasUnsavedUntitled, "保存后未保存标记必须清除")
        // 内容已落盘
        let written = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(written, "# modified")
    }

    // MARK: - 保存失败时窗口保持打开

    func testSaveFailureKeepsWindowOpen() async throws {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: dirty)

        // 指向一个不存在的目录路径，写入必然失败
        let badURL = URL(fileURLWithPath: "/nonexistent-root-dir-\(UUID().uuidString)/x.md")
        interaction.promptChoice = .save
        interaction.saveTarget = badURL

        let decision = await termCoord.resolveUnsavedChanges(for: dirty)

        XCTAssertEqual(decision, .cancel, "写入失败应返回 cancel")
        XCTAssertTrue(dirty.documentViewModel.isUntitled, "失败后 isUntitled 必须保留")
        XCTAssertTrue(dirty.documentViewModel.isDirty, "失败后 isDirty 必须保留")
        XCTAssertTrue(dirty.appViewModel.hasUnsavedUntitled, "失败后未保存标记必须保留")
        XCTAssertNotNil(dirty.documentViewModel.fileError, "失败后必须呈现 fileError")
    }

    // MARK: - 取消保存面板时窗口保持打开

    func testCancelSavePanelKeepsWindowOpen() async {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: dirty)

        interaction.promptChoice = .save
        interaction.saveTarget = nil  // 用户取消保存面板

        let decision = await termCoord.resolveUnsavedChanges(for: dirty)

        XCTAssertEqual(decision, .cancel, "取消保存面板应返回 cancel")
        XCTAssertTrue(dirty.documentViewModel.isUntitled, "取消后 Untitled 内容必须保留")
        XCTAssertEqual(dirty.documentViewModel.content, "# modified", "内容不得丢失")
    }

    // MARK: - 取消提示时窗口保持打开

    func testCancelPromptKeepsContent() async {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: dirty)

        interaction.promptChoice = .cancel

        let decision = await termCoord.resolveUnsavedChanges(for: dirty)

        XCTAssertEqual(decision, .cancel)
        XCTAssertTrue(dirty.documentViewModel.isUntitled)
        XCTAssertEqual(dirty.documentViewModel.content, "# modified")
    }

    // MARK: - 「不保存」只清理所属 session

    func testDontSaveDiscardsOnlyOwningSession() async {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let dirty = makeSession(coordinator: coordinator, dirty: true)
        let clean = makeSession(coordinator: coordinator)
        coordinator.register(session: dirty)
        coordinator.register(session: clean)

        interaction.promptChoice = .dontSave

        let decision = await termCoord.resolveUnsavedChanges(for: dirty)

        XCTAssertEqual(decision, .proceed)
        XCTAssertFalse(dirty.documentViewModel.isUntitled, "dirty session 已被丢弃")
        XCTAssertFalse(dirty.documentViewModel.isDirty)
        // clean session 不受影响
        XCTAssertFalse(clean.documentViewModel.isUntitled)
    }

    // MARK: - 多脏窗口退出串行处理

    func testMultipleDirtyWindowsProcessedSerially() async throws {
        let (coordinator, termCoord, _) = makeCoordinatorAndInteraction()
        let d1 = makeSession(coordinator: coordinator, dirty: true)
        let d2 = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: d1)
        coordinator.register(session: d2)

        let url1 = try makeFile(named: "d1.md", content: "")
        let url2 = try makeFile(named: "d2.md", content: "")
        let seqInteraction = SequentialSaveInteraction(targets: [url1, url2], prompt: .save)
        termCoord.setCloseInteraction(seqInteraction)

        XCTAssertTrue(termCoord.beginTermination())
        await termCoord.processTermination()

        // 两个脏窗口都被串行处理：内容落盘、Untitled 清除
        XCTAssertFalse(d1.documentViewModel.isUntitled)
        XCTAssertFalse(d2.documentViewModel.isUntitled)
        XCTAssertEqual(termCoord.state, .terminating)
        XCTAssertEqual(try String(contentsOf: url1, encoding: .utf8), "# modified")
    }

    // MARK: - 重复 Cmd+Q 不产生多个 termination reply

    func testRepeatedCmdQDoesNotDuplicateReply() async {
        let (coordinator, termCoord, _) = makeCoordinatorAndInteraction()
        _ = coordinator

        // 第一次 beginTermination 切到 processing
        XCTAssertTrue(termCoord.beginTermination(), "首次 beginTermination 应成功")
        // 第二次在 processing 期间返回 false
        XCTAssertFalse(termCoord.beginTermination(), "processing 期间重复 beginTermination 必须返回 false")
        // 复位以便后续测试
        termCoord.resetStateForTesting()
    }

    // MARK: - 任一窗口取消时终止整个退出流程

    func testCancellationStopsTermination() async {
        let (coordinator, termCoord, interaction) = makeCoordinatorAndInteraction()
        let d1 = makeSession(coordinator: coordinator, dirty: true)
        let d2 = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: d1)
        coordinator.register(session: d2)

        interaction.promptChoice = .cancel  // 第一个即取消

        XCTAssertTrue(termCoord.beginTermination())
        await termCoord.processTermination()

        // 取消后应复位 idle，允许下次尝试
        XCTAssertEqual(termCoord.state, .idle, "取消后必须复位 idle")
    }

    // MARK: - 全部保存成功后完成退出

    func testAllSavedCompletesTermination() async throws {
        let (coordinator, termCoord, _) = makeCoordinatorAndInteraction()
        let d1 = makeSession(coordinator: coordinator, dirty: true)
        let d2 = makeSession(coordinator: coordinator, dirty: true)
        coordinator.register(session: d1)
        coordinator.register(session: d2)

        let url1 = try makeFile(named: "s1.md", content: "")
        let url2 = try makeFile(named: "s2.md", content: "")
        let seqInteraction = SequentialSaveInteraction(targets: [url1, url2], prompt: .save)
        termCoord.setCloseInteraction(seqInteraction)

        XCTAssertTrue(termCoord.beginTermination())
        await termCoord.processTermination()

        XCTAssertEqual(termCoord.state, .terminating, "全部保存成功后应切到 terminating")
        XCTAssertFalse(d1.documentViewModel.isUntitled)
        XCTAssertFalse(d2.documentViewModel.isUntitled)
    }

    // MARK: - 无脏窗口直接放行退出

    func testNoDirtyWindowsProceedsImmediately() async {
        let (coordinator, termCoord, _) = makeCoordinatorAndInteraction()
        let clean = makeSession(coordinator: coordinator)
        coordinator.register(session: clean)

        XCTAssertTrue(termCoord.beginTermination())
        await termCoord.processTermination()

        XCTAssertEqual(termCoord.state, .terminating)
    }
}

/// 顺序返回保存目标的 fake：第 n 次调用返回 targets[n]。
@MainActor
final class SequentialSaveInteraction: UnsavedCloseInteraction {
    let targets: [URL]
    let prompt: UnsavedPromptChoice
    private var callIndex = 0

    init(targets: [URL], prompt: UnsavedPromptChoice) {
        self.targets = targets
        self.prompt = prompt
    }

    func presentUnsavedChangesPrompt(for session: WindowSession) -> UnsavedPromptChoice {
        prompt
    }

    func chooseSaveAsTarget(
        for session: WindowSession,
        suggestedName: String,
        defaultDirectory: URL?
    ) async -> URL? {
        guard callIndex < targets.count else { return nil }
        let url = targets[callIndex]
        callIndex += 1
        return url
    }
}
