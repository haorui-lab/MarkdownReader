import XCTest
@testable import MarkdownReader

/// Task 10：窗口级 Undo 隔离测试。
@MainActor
final class WindowUndoStoreTests: TemporaryDirectoryTestCase {

    // MARK: - 两个 store 对同一 URL 返回不同 manager

    func testTwoStoresReturnDifferentManagersForSameURL() throws {
        let url = try makeFile(named: "a.md", content: "x")
        let storeA = WindowUndoStore()
        let storeB = WindowUndoStore()

        storeA.switchFile(to: url)
        storeB.switchFile(to: url)

        let managerA = storeA.undoManager(for: url)
        let managerB = storeB.undoManager(for: url)

        XCTAssertNotNil(managerA)
        XCTAssertNotNil(managerB)
        XCTAssertFalse(managerA === managerB,
                       "两个窗口的同一文件 undo manager 必须不同")
    }

    // MARK: - 切换文件只改变一个 store 的活跃 manager

    func testSwitchingFileChangesOnlyOneStoreActiveManager() throws {
        let urlA = try makeFile(named: "a.md", content: "x")
        let urlB = try makeFile(named: "b.md", content: "y")
        let storeA = WindowUndoStore()
        let storeB = WindowUndoStore()

        storeA.switchFile(to: urlA)
        storeB.switchFile(to: urlA)

        // storeA 切换到 urlB，storeB 仍在 urlA
        storeA.switchFile(to: urlB)

        XCTAssertEqual(storeA.activeFileURL, urlB)
        XCTAssertEqual(storeB.activeFileURL, urlA)
        XCTAssertFalse(storeA.activeUndoManager === storeB.activeUndoManager)
    }

    // MARK: - 迁移 undo 历史到新 URL

    func testMigrationMovesManagerToNewURL() throws {
        let oldURL = try makeFile(named: "old.md", content: "x")
        let newURL = try makeFile(named: "new.md", content: "y")
        let store = WindowUndoStore()

        store.switchFile(to: oldURL)
        let oldManager = store.undoManager(for: oldURL)

       store.migrate(from: oldURL, to: newURL)

       let newManager = store.undoManager(for: newURL)
       XCTAssertTrue(oldManager === newManager,
                      "迁移后新 URL 应复用旧 URL 的 manager")
        // 旧 URL 的 manager 已迁移走；undoManager(for:) 会为新查询创建新 manager
        XCTAssertFalse(store.undoManager(for: oldURL) === oldManager,
                      "旧 URL 不应再持有原 manager")
       XCTAssertEqual(store.activeFileURL, newURL)
    }

    // MARK: - 移除一个 store 的 undo 不影响另一个

    func testRemovingOneStoreActionsDoesNotClearOtherStore() throws {
        let url = try makeFile(named: "shared.md", content: "x")
        let storeA = WindowUndoStore()
        let storeB = WindowUndoStore()

        storeA.switchFile(to: url)
        storeB.switchFile(to: url)

        let managerA = storeA.undoManager(for: url)!
        let managerB = storeB.undoManager(for: url)!

        // 模拟 undo 动作注册
        managerA.beginUndoGrouping()
        managerA.registerUndo(withTarget: self) { _ in }
        managerA.endUndoGrouping()

        managerB.beginUndoGrouping()
        managerB.registerUndo(withTarget: self) { _ in }
        managerB.endUndoGrouping()

        XCTAssertTrue(managerA.canUndo)
        XCTAssertTrue(managerB.canUndo)

        // 清空 storeA 的 undo，storeB 不受影响
        storeA.removeAllActions()

        XCTAssertFalse(managerA.canUndo)
        XCTAssertTrue(managerB.canUndo, "storeB 的 undo 历史不应被 storeA 清空影响")
    }
}
