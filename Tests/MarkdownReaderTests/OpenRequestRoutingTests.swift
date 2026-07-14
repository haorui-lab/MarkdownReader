import XCTest
@testable import MarkdownReader

/// Task 8：统一打开路由测试。
@MainActor
final class OpenRequestRoutingTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    private func makeCoordinator() -> WindowCoordinator {
        WindowCoordinator(identityService: identityService)
    }

    private func fileURL(_ name: String) -> URL {
        try! makeFile(named: name, content: "# \(name)")
    }

    // MARK: - 队列与 drain

    func testAllExternalURLsAreQueued() {
        let coordinator = makeCoordinator()
        let urls = [fileURL("a.md"), fileURL("b.md"), fileURL("c.md")]
        let request = OpenRequest(urls: urls, source: .external)
        coordinator.enqueue(request)
        XCTAssertEqual(coordinator.pendingRequestCount, 1)
    }

    func testColdStartRequestWinsOverRestoreRequest() {
        let coordinator = makeCoordinator()
        let externalURL = fileURL("external.md")
        let restoreRequest = OpenRequest(urls: [], source: .openRecent)
        let externalRequest = OpenRequest(url: externalURL, source: .external)
        coordinator.enqueue(restoreRequest)
        coordinator.enqueue(externalRequest)
        let processed = coordinator.drainPendingRequests()
        XCTAssertTrue(processed.contains { $0.source == .external })
    }

    // MARK: - 路由决策

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
