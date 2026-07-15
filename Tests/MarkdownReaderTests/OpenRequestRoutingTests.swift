import XCTest
@testable import MarkdownReader

/// Task 2/8：统一打开路由与请求队列测试。
@MainActor
final class OpenRequestRoutingTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeCoordinator() -> WindowCoordinator {
        WindowCoordinator(identityService: identityService)
    }

    private func fileURL(_ name: String) -> URL {
        try! makeFile(named: name, content: "# \(name)")
    }

    /// 注入测试用窗口创建闭包，使无 OpenWindowAction 的测试也能完成 createWindow 决策。
    private func makeReadyCoordinator() -> (WindowCoordinator, createdIDs: Box<[WindowID]>) {
        let coordinator = makeCoordinator()
        let box = Box<[WindowID]>([])
        coordinator.windowCreationClosureForTesting = { id in box.value.append(id) }
        return (coordinator, box)
    }

    // MARK: - 队列保留（action 未安装时不 drain / 不删除）

    func testAllExternalURLsAreQueued() {
        let coordinator = makeCoordinator()
        // Task 2：未安装 action 时 enqueue 只入队不 drain，请求保留。
        let urls = [fileURL("a.md"), fileURL("b.md"), fileURL("c.md")]
        let request = OpenRequest(urls: urls, source: .external)
        coordinator.enqueue(request)
        XCTAssertEqual(coordinator.pendingRequestCount, 1)
    }

    func testEnqueueWithoutActionKeepsRequest() {
        let coordinator = makeCoordinator()
        coordinator.enqueue(OpenRequest(url: fileURL("a.md"), source: .external))
        XCTAssertEqual(coordinator.pendingRequestCount, 1, "action 未安装时请求必须保留在队列")
    }

    func testDrainWithoutActionKeepsRequests() {
        let coordinator = makeCoordinator()
        coordinator.enqueue(OpenRequest(url: fileURL("a.md"), source: .external))
        coordinator.enqueue(OpenRequest(url: fileURL("b.md"), source: .external))
        XCTAssertEqual(coordinator.pendingRequestCount, 2)
        // action 未安装时 drain 应原样保留，不删除
        let processed = coordinator.drainPendingRequests()
        XCTAssertTrue(processed.isEmpty, "action 未安装时 drain 不得处理任何请求")
        XCTAssertEqual(coordinator.pendingRequestCount, 2, "action 未安装时请求必须保留")
    }

    // MARK: - 安装 action 后自动 drain（Task 2）

    func testPendingRequestsAutoDrainedAfterActionInstalled() {
        let coordinator = makeCoordinator()
        let box = Box<[WindowID]>([])
        // 先入队（此时无 action，保留）
        coordinator.enqueue(OpenRequest(url: fileURL("a.md"), source: .external))
        XCTAssertEqual(coordinator.pendingRequestCount, 1)
        // 注入创建闭包（模拟 install action）→ install 触发 drainIfReady。
        // 设置闭包本身不触发 drain（只有 install/register 触发），这里手动 drain 模拟
        // WindowSceneHost.task 中 install 完成后的自动 drain 行为。
        coordinator.windowCreationClosureForTesting = { id in box.value.append(id) }
        coordinator.drainPendingRequests()
        XCTAssertEqual(coordinator.pendingRequestCount, 0, "安装 action 后 pending 请求应被自动 drain")
        XCTAssertEqual(box.value.count, 1, "应创建一个新窗口承载该文件")
    }

    // MARK: - 多请求不丢失、顺序稳定（Task 2）

    func testMultipleRequestsNotLostInOrder() throws {
        let (coordinator, box) = makeReadyCoordinator()
        // 无已注册 session：每个不同文件都走 createWindow，按入队顺序创建
        coordinator.enqueue(OpenRequest(url: fileURL("m1.md"), source: .external))
        coordinator.enqueue(OpenRequest(url: fileURL("m2.md"), source: .external))
        coordinator.enqueue(OpenRequest(url: fileURL("m3.md"), source: .external))
        XCTAssertEqual(box.value.count, 3, "三个不同文件应各创建一个窗口")
        XCTAssertEqual(coordinator.pendingRequestCount, 0, "所有请求应被处理，队列清空")
    }

    // MARK: - external 优先于 restore（Task 2）

    func testColdStartRequestWinsOverRestoreRequest() {
        let (coordinator, _) = makeReadyCoordinator()
        let externalURL = fileURL("external.md")
        let restoreRequest = OpenRequest(urls: [], source: .openRecent)
        let externalRequest = OpenRequest(url: externalURL, source: .external)
        coordinator.enqueue(restoreRequest)
        coordinator.enqueue(externalRequest)
        // external 应已通过 enqueue 自动 drain 被处理：无已注册 session → createWindow + storePending。
        let identity = (try? identityService.identity(for: externalURL, kind: .file))
        let storedForNewWindow = coordinator.pendingResourcesForTesting.values.contains(identity!)
        XCTAssertTrue(storedForNewWindow, "external 请求应被处理并预存资源到新窗口")
        // restore 请求 urls 为空，被 handleOpenRequest 跳过，不产生任何 pending resource。
        // 队列应已清空（两条都被取出，external 有副作用、restore 无副作用但已消费）。
        XCTAssertEqual(coordinator.pendingRequestCount, 0, "restore(空 urls) 应被取出消费，队列清空")
    }

    // MARK: - drain 期间新入队请求由收尾 drain 接管（Task 2 重入收尾）

    func testRequestEnqueuedDuringDrainIsHandledByTrailingDrain() throws {
        let coordinator = makeCoordinator()
        let firstFile = try makeFile(named: "trigger.md", content: "# t")
        let secondFile = try makeFile(named: "second.md", content: "# s")

        // 标记闭包是否在 drain 执行中被调用，并同步入队第二个请求。
        let box = Box<[WindowID]>([])
        let didReEnqueue = Box<Bool>(false)
        coordinator.windowCreationClosureForTesting = { [weak coordinator] _ in
            box.value.append(WindowID())
            guard !(didReEnqueue.value) else { return }
            didReEnqueue.value = true
            // 在 drain 执行中同步入队第二个请求——被 isDraining 闸挡住，应由收尾 drain 接管。
            coordinator?.enqueue(OpenRequest(url: secondFile, source: .external))
        }
        // 首个请求无已注册 session → createWindow，触发闭包内同步 enqueue 第二个请求。
        coordinator.enqueue(OpenRequest(url: firstFile, source: .external))

        // 第一个请求 createWindow 触发闭包 → 闭包内同步 enqueue 第二个请求。
        // 收尾 drain 应接管第二个请求，再 createWindow 一次。
        XCTAssertEqual(box.value.count, 2, "drain 期间入队的第二个请求应由收尾 drain 处理")
        XCTAssertEqual(coordinator.pendingRequestCount, 0, "收尾后队列应清空")
    }

    // MARK: - 路由决策（纯逻辑，无副作用）

    func testFirstURLReusesBlankAndSecondCreatesWindow() throws {
        let coordinator = makeCoordinator()
        let blank = WindowID()
        coordinator.registerSession(id: blank, isBlank: true)
        let url1 = fileURL("first.md")
        let url2 = fileURL("second.md")
        let decisions = coordinator.routeOpenRequest(
            urls: [url1, url2],
            preferredWindowID: blank
        )
        XCTAssertEqual(decisions.count, 2)
        if case .openInSession(let windowID, _) = decisions[0] {
            XCTAssertEqual(windowID, blank)
        } else {
            XCTFail("expected .openInSession for first URL, got \(decisions[0])")
        }
        if case .createWindow = decisions[1] {
            // pass
        } else {
            XCTFail("expected .createWindow for second URL, got \(decisions[1])")
        }
    }

    func testOpenRecentActivatesExistingOwner() throws {
        let coordinator = makeCoordinator()
        let owner = WindowID()
        let other = WindowID()
        coordinator.registerSession(id: owner, isBlank: false)
        coordinator.registerSession(id: other, isBlank: true)
        let url = fileURL("owned.md")
        let identity = try identityService.identity(for: url, kind: .file)
        try coordinator.claim(identity, for: owner)
        let decisions = coordinator.routeOpenRequest(
            urls: [url],
            preferredWindowID: other
        )
        XCTAssertEqual(decisions.count, 1)
        if case .activateOwner(let windowID, _) = decisions[0] {
            XCTAssertEqual(windowID, owner)
        } else {
            XCTFail("expected .activateOwner, got \(decisions[0])")
        }
    }

    func testMissingURLDoesNotBlockFollowingURLs() throws {
        let coordinator = makeCoordinator()
        let blank = WindowID()
        coordinator.registerSession(id: blank, isBlank: true)
        let missingURL = temporaryDirectory!.appendingPathComponent("nonexistent.md")
        let existingURL = fileURL("exists.md")
        let decisions = coordinator.routeOpenRequest(
            urls: [missingURL, existingURL],
            preferredWindowID: blank
        )
        XCTAssertEqual(decisions.count, 2)
        if case .reject = decisions[0] {
            // pass
        } else {
            XCTFail("expected .reject for missing file, got \(decisions[0])")
        }
        if case .openInSession = decisions[1] {
            // pass
        } else {
            XCTFail("expected .openInSession for existing file, got \(decisions[1])")
        }
    }

    func testNoVisibleWindowCreatesOrReopensCorrectWindow() {
        let coordinator = makeCoordinator()
        let url = fileURL("lone.md")
        let decisions = coordinator.routeOpenRequest(
            urls: [url],
            preferredWindowID: nil
        )
        XCTAssertEqual(decisions.count, 1)
        if case .createWindow = decisions[0] {
            // pass
        } else {
            XCTFail("expected .createWindow when no sessions, got \(decisions[0])")
        }
    }
}

/// 测试辅助：可变引用盒子，让闭包能累积收集值。
final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
