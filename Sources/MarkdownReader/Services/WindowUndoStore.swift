import Foundation
import AppKit

/// 窗口级 Undo 管理器存储（Task 10）。
///
/// 替代全局 `UndoManagerProvider.shared`：每个 `WindowSession` 持有一个 store，
/// undo 历史按窗口隔离。通过 ObjC associated object 绑定到 `NSWindow`，
/// 使 swizzled `undoManager` getter 无需全局可变状态即可返回当前窗口的活跃 manager。
///
/// 线程安全：所有方法在 `@MainActor` 执行；associated object 读取也在主线程。
@MainActor
final class WindowUndoStore {

    /// 按 URL 缓存的 UndoManager（per-file within this window）。
    private var managers: [URL: UndoManager] = [:]

    /// 当前活跃文件 URL（决定 undo 菜单作用目标）。
    private(set) var activeFileURL: URL?

    /// 当前活跃 UndoManager。
    var activeUndoManager: UndoManager {
        if let url = activeFileURL, let existing = managers[url] {
            return existing
        }
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        if let url = activeFileURL {
            managers[url] = manager
        }
        return manager
    }

    /// 获取指定文件的 UndoManager（不存在则创建）。
    func undoManager(for url: URL?) -> UndoManager? {
        guard let url else { return nil }
        if let existing = managers[url] {
            return existing
        }
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        managers[url] = manager
        return manager
    }

    /// 切换活跃文件，更新 undo 菜单目标。
    func switchFile(to url: URL?) {
        activeFileURL = url
        if let url, managers[url] == nil {
            let manager = UndoManager()
            manager.levelsOfUndo = 100
            managers[url] = manager
        }
    }

    /// 迁移 undo 历史到新 URL（用于另存为）。
    func migrate(from oldURL: URL, to newURL: URL) {
        guard let manager = managers[oldURL] else {
            // 旧 URL 无历史，直接确保新 URL 有 manager
            if managers[newURL] == nil {
                let m = UndoManager()
                m.levelsOfUndo = 100
                managers[newURL] = m
            }
            return
        }
        managers[newURL] = manager
        managers.removeValue(forKey: oldURL)
        if activeFileURL == oldURL {
            activeFileURL = newURL
        }
    }

    /// 移除指定文件的 undo 历史。
    func remove(for url: URL) {
        managers[url]?.removeAllActions()
        managers.removeValue(forKey: url)
        if activeFileURL == url {
            activeFileURL = nil
        }
    }

    /// 清空所有 undo 历史（窗口关闭时调用）。
    func removeAllActions() {
        for (_, um) in managers {
            um.removeAllActions()
        }
        managers.removeAll()
        activeFileURL = nil
    }
}

// MARK: - NSWindow Associated Object

extension NSWindow {

    private static var storeKey: UInt8 = 0

    /// 绑定到窗口的 WindowUndoStore（弱引用，store 由 WindowSession 持有）。
    /// swizzled undoManager getter 通过此属性获取当前窗口的活跃 manager。
    var undoStore: WindowUndoStore? {
        get { objc_getAssociatedObject(self, &Self.storeKey) as? WindowUndoStore }
        set { objc_setAssociatedObject(self, &Self.storeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
