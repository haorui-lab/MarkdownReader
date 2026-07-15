import XCTest
@testable import MarkdownReader

import SwiftUI
import AppKit

/// 回归修复 §四 + 测试矩阵：多窗口连带问题测试。
///
/// 覆盖：外部去重（再次打开已持有文件只激活原窗口）、Markdown 内链只由来源窗口处理、
/// 全屏状态隔离、key 切换更新 MRU、Cmd+Shift+N 连续创建窗口。
@MainActor
final class MultiWindowRegressionTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeSession(coordinator: WindowCoordinator) -> WindowSession {
        WindowSession(id: WindowID(), coordinator: coordinator)
    }

    // MARK: - 外部去重：再次打开已持有文件只激活原窗口

    func testExternalOpenOfOwnedFileActivatesOwner() throws {
        let coordinator = WindowCoordinator()
        let created = CreatedWindowsBox()
        coordinator.windowCreationClosureForTesting = { id in created.ids.append(id) }

        let owner = makeSession(coordinator: coordinator)
        let other = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: other)

        let a = try makeFile(named: "A.md", content: "# A")
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: owner.id)

        let countBefore = created.ids.count
        // 经外部打开路由再次打开 A.md：应激活 owner，不创建新窗口
        coordinator.enqueue(OpenRequest(url: a, source: .external, preferredWindowID: other.id))
        // action 已安装（测试闭包），drain 同步执行
        _ = coordinator.drainPendingRequests()

        XCTAssertEqual(created.ids.count, countBefore, "再次打开已持有文件不得创建新窗口")
        XCTAssertEqual(coordinator.lastActiveWindowID, owner.id, "应激活所有者窗口")
    }

    // MARK: - Markdown 内链只由来源窗口处理：owner 持有时激活 owner，不抢所有权

    func testLinkedMarkdownFileOwnedByOtherActivatesOwner() throws {
        let coordinator = WindowCoordinator()
        let owner = makeSession(coordinator: coordinator)
        let source = makeSession(coordinator: coordinator)
        coordinator.register(session: owner)
        coordinator.register(session: source)

        let a = try makeFile(named: "A.md", content: "# A")
        let b = try makeFile(named: "B.md", content: "# B")
        try coordinator.claim(identityService.identity(for: a, kind: .file), for: owner.id)
        // 来源窗口当前显示 B.md
        source.documentViewModel.currentFileURL = b
        source.fileTreeViewModel.selectedFileURL = b

        // 来源窗口的内链回调点击 A.md（已被 owner 持有）
        source.handleLinkedMarkdownFile(a)

        XCTAssertEqual(source.documentViewModel.currentFileURL, b, "来源窗口文档不得被抢占")
        XCTAssertEqual(source.fileTreeViewModel.selectedFileURL, b, "来源窗口选中项不得改变")
        XCTAssertEqual(coordinator.lastActiveWindowID, owner.id, "应激活所有者窗口")
    }

    // MARK: - 全屏状态按窗口隔离：A 的 isFullScreen 不影响 B

    func testFullScreenStateIsolatedPerWindow() {
        let coordinator = WindowCoordinator()
        let a = makeSession(coordinator: coordinator)
        let b = makeSession(coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)

        XCTAssertFalse(a.appViewModel.isFullScreen)
        XCTAssertFalse(b.appViewModel.isFullScreen)

        // 模拟 A 进入全屏（FullScreenStateModifier 按 NSWindow 过滤，只更新 A 的 appViewModel）
        a.appViewModel.isFullScreen = true

        XCTAssertTrue(a.appViewModel.isFullScreen, "A 进入全屏")
        XCTAssertFalse(b.appViewModel.isFullScreen, "B 的全屏状态不得被 A 改变")
    }

    // MARK: - key 切换更新 MRU：关闭当前活动窗口回退到上一个活动窗口

    func testKeySwitchUpdatesMRUAndCloseFallsBack() {
        let coordinator = WindowCoordinator()
        let a = makeSession(coordinator: coordinator)
        let b = makeSession(coordinator: coordinator)
        let c = makeSession(coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)
        coordinator.register(session: c)

        // 模拟用户点击切换 key window：a → b → c
        coordinator.recordActive(windowID: a.id)
        coordinator.recordActive(windowID: b.id)
        coordinator.recordActive(windowID: c.id)
        XCTAssertEqual(coordinator.lastActiveWindowID, c.id)

        // 关闭当前活动窗口 c：回退到上一个活动窗口 b
        c.dispose()
        XCTAssertEqual(coordinator.lastActiveWindowID, b.id, "关闭当前活动窗口后回退到 MRU 上一个")
    }

    // MARK: - Cmd+Shift+N 连续创建多个空白窗口

    func testOpenBlankWindowCreatesDistinctWindows() {
        let coordinator = WindowCoordinator()
        let created = CreatedWindowsBox()
        coordinator.windowCreationClosureForTesting = { id in created.ids.append(id) }

        // 连续创建 5 个空白窗口
        for _ in 0..<5 {
            coordinator.openBlankWindow()
        }

        XCTAssertEqual(created.ids.count, 5, "应连续创建 5 个空白窗口")
        // 每个 windowID 互不相同
        let uniqueIDs = Set(created.ids)
        XCTAssertEqual(uniqueIDs.count, 5, "每个空白窗口应有唯一 windowID")
        // 每个 windowID 都预存了 nil 资源（空白）
        for id in created.ids {
            XCTAssertNil(coordinator.consumePendingResource(for: id), "空白窗口不得携带待加载资源")
        }
    }

    // MARK: - Window 菜单可激活目标窗口

    func testActivateWindowMovesToMRUEnd() {
        let coordinator = WindowCoordinator()
        let a = makeSession(coordinator: coordinator)
        let b = makeSession(coordinator: coordinator)
        coordinator.register(session: a)
        coordinator.register(session: b)

        coordinator.recordActive(windowID: a.id)
        coordinator.recordActive(windowID: b.id)
        XCTAssertEqual(coordinator.lastActiveWindowID, b.id)

        // Window 菜单激活 a
        coordinator.activate(windowID: a.id)
        XCTAssertEqual(coordinator.lastActiveWindowID, a.id, "激活 a 后 a 应成为最近活动窗口")
    }

    // MARK: - ContentView 布局尺寸：FullScreenStateModifier 不得导致布局塌缩

    /// ContentView 经 FullScreenStateModifier 修饰后，根视图必须向窗口报告
    /// 不小于 650x450 的有效布局尺寸。此前 .overlay(content) 导致根视图报告零尺寸，
    /// 界面只靠 minWidth/minHeight 溢出绘制，全屏后出现中央小窗口。
    func testContentViewReportsValidLayoutSize() {
        let coordinator = WindowCoordinator()
        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)

        let view = ContentView(session: session)
        let hosting = NSHostingController(rootView: view)
        let size = hosting.sizeThatFits(in: NSSize(width: 10000, height: 10000))

        XCTAssertGreaterThanOrEqual(size.width, 650,
            "ContentView 宽度不得因 FullScreenAnchor 塌缩为零（实际: \(size.width)）")
        XCTAssertGreaterThanOrEqual(size.height, 450,
            "ContentView 高度不得因 FullScreenAnchor 塌缩为零（实际: \(size.height)）")
    }

    // MARK: - 全屏通知按窗口隔离：A 的通知不更新 B

    /// A 窗口收到 didEnterFullScreen 通知时只更新 A 的 isFullScreen，
    /// B 窗口不受影响。验证 FullScreenObserverView 按 NSWindow 过滤逻辑。
    func testFullScreenNotificationFilteredByWindow() {
        let coordinator = WindowCoordinator()
        let sessionA = makeSession(coordinator: coordinator)
        let sessionB = makeSession(coordinator: coordinator)
        coordinator.register(session: sessionA)
        coordinator.register(session: sessionB)

        let windowA = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        let windowB = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )

        let hostingA = NSHostingController(rootView: ContentView(session: sessionA))
        let hostingB = NSHostingController(rootView: ContentView(session: sessionB))
        windowA.contentView = hostingA.view
        windowB.contentView = hostingB.view

        // 等待 SwiftUI 视图挂载，触发 viewDidMoveToWindow
        flushMainQueue()

        XCTAssertFalse(sessionA.appViewModel.isFullScreen, "A 初始非全屏")
        XCTAssertFalse(sessionB.appViewModel.isFullScreen, "B 初始非全屏")

        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification, object: windowA
        )
        flushMainQueue()

        XCTAssertTrue(sessionA.appViewModel.isFullScreen, "A 收到全屏通知后应进入全屏")
        XCTAssertFalse(sessionB.appViewModel.isFullScreen, "B 不受 A 的全屏通知影响")

        NotificationCenter.default.post(
            name: NSWindow.didExitFullScreenNotification, object: windowA
        )
        flushMainQueue()

        XCTAssertFalse(sessionA.appViewModel.isFullScreen, "A 退出全屏")
        XCTAssertFalse(sessionB.appViewModel.isFullScreen, "B 仍非全屏")

        windowA.contentView = nil
        windowB.contentView = nil
    }

    // MARK: - observer 重新挂载窗口后不重复响应旧窗口通知

    /// FullScreenObserverView 从 windowA 移到 windowB 后，windowA 的全屏通知
    /// 不得再更新本 session 的 isFullScreen。验证 viewDidMoveToWindow 中
    /// 先移除旧 observer 再注册新 observer 的逻辑。
    func testObserverReattachDoesNotRespondToOldWindow() {
        let coordinator = WindowCoordinator()
        let session = makeSession(coordinator: coordinator)
        coordinator.register(session: session)

        let windowA = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        let windowB = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )

        let hosting = NSHostingController(rootView: ContentView(session: session))
        windowA.contentView = hosting.view

        flushMainQueue()

        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification, object: windowA
        )
        flushMainQueue()
        XCTAssertTrue(session.appViewModel.isFullScreen, "挂载在 windowA 时应响应其全屏通知")

        NotificationCenter.default.post(
            name: NSWindow.didExitFullScreenNotification, object: windowA
        )
        flushMainQueue()
        XCTAssertFalse(session.appViewModel.isFullScreen)

        // 转移到 windowB
        windowA.contentView = nil
        windowB.contentView = hosting.view
        flushMainQueue()

        // windowA 的通知不应再影响本 session
        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification, object: windowA
        )
        flushMainQueue()
        XCTAssertFalse(session.appViewModel.isFullScreen,
            "重新挂载到 windowB 后，windowA 的通知不得再更新本 session")

        // windowB 的通知应正常响应
        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification, object: windowB
        )
        flushMainQueue()
        XCTAssertTrue(session.appViewModel.isFullScreen,
            "挂载在 windowB 时应响应其全屏通知")

        windowB.contentView = nil
    }

    // MARK: - 辅助

    /// 处理主队列上已排入的异步任务（Task { @MainActor in ... }），
    /// 使全屏通知回调中的状态写入在断言前生效。
    private func flushMainQueue() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}
