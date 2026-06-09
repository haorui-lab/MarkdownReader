import SwiftUI
import MarkdownReaderKit
import os

/// 应用委托，处理 macOS 应用生命周期事件
///
/// macOS 15+ 上 SwiftUI WindowGroup 在收到文件打开事件时可能创建不可见窗口。
/// 修复策略：
/// - 冷启动：applicationDidFinishLaunching 延迟后主动发送 .openFile/.openDirectory 通知
/// - ContentView.task 作为极早期后备（在 AppDelegate 延迟前已挂载时）
/// - UserDefaults 是协调点：无论谁先处理，都会清除 key，避免重复打开
/// - 热启动有窗口：直接发送通知
/// - 热启动无窗口：激活 SwiftUI 创建的不可见窗口，然后发送通知
/// - Dock 点击无窗口：激活不可见窗口，重置为欢迎页
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.markdownreader.app", category: "AppDelegate")

    /// 冷启动时记录待处理的文件 URL
    var pendingOpenFileURL: URL?

    /// 冷启动时记录待处理的目录 URL
    var pendingOpenDirectoryURL: URL?

    /// 应用是否已经完成启动（用于区分冷启动和热启动）
    private var didFinishLaunching = false

    /// 应用即将完成启动
    func applicationWillFinishLaunching(_ notification: Notification) {
        logger.info("applicationWillFinishLaunching")
    }

    // MARK: - 窗口辅助

    /// 激活第一个不可见的可成为 key 的窗口（SwiftUI WindowGroup 创建的）
    /// SwiftUI 有时会创建不可见窗口来处理文件打开事件，需要手动激活
    /// 使用 canBecomeKey + isSheet + isPanel 判断，避免依赖私有类名
    private func activateFirstHiddenWindow() {
        for window in NSApp.windows {
            if !window.isSheet && window.canBecomeKey && !(window is NSPanel) {
                if !window.isVisible || window.isMiniaturized {
                    logger.info("Activating hidden window: title='\(window.title)'")
                    window.deminiaturize(nil)
                    window.setIsVisible(true)
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                }
                break
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 检查是否有可见窗口
    private func hasVisibleWindows() -> Bool {
        NSApp.windows.contains { $0.isVisible && !$0.isSheet }
    }

    // MARK: - 文件打开回调

    /// macOS 13+ URL 版本的文件打开回调
    /// 冷启动时在 applicationDidFinishLaunching 之前调用
    /// 热启动时直接调用
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("application(_:open:) called with \(urls.count) URLs")
        guard let url = urls.first else { return }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        // 存储到 UserDefaults，作为 ContentView.task 的后备读取路径
        if isDir.boolValue {
            pendingOpenDirectoryURL = url
            UserDefaults.standard.set(url.path as String, forKey: "pendingOpenDirectoryPath")
            UserDefaults.standard.removeObject(forKey: "pendingOpenFilePath")
        } else {
            pendingOpenFileURL = url
            UserDefaults.standard.set(url.path as String, forKey: "pendingOpenFilePath")
            UserDefaults.standard.removeObject(forKey: "pendingOpenDirectoryPath")
        }
        // 不需要手动 synchronize()，UserDefaults 会自动定期同步到磁盘

        if didFinishLaunching {
            // 热启动
            if hasVisibleWindows() {
                logger.info("Hot start: has visible window — posting notification")
                DispatchQueue.main.async {
                    let name: Notification.Name = isDir.boolValue ? .openDirectory : .openFile
                    NotificationCenter.default.post(name: name, object: url)
                }
            } else {
                // 无可见窗口：SwiftUI 可能创建了不可见窗口
                logger.info("Hot start: no visible window — activating hidden window + posting notification")
                activateFirstHiddenWindow()
                // 使用 async 而非 asyncAfter(0.3)，避免不必要的 300ms 延迟
                // activateFirstHiddenWindow 同步完成窗口激活，下一个 runloop 周期即可安全发通知
                DispatchQueue.main.async {
                    let name: Notification.Name = isDir.boolValue ? .openDirectory : .openFile
                    NotificationCenter.default.post(name: name, object: url)
                }
            }
        } else {
            logger.info("Cold start: stored pending URL")
        }
    }

    // MARK: - 应用生命周期

    /// 应用启动完成后，处理冷启动场景
    /// 策略：AppDelegate 主动发送通知打开文件，不再依赖 ContentView.task 读取 UserDefaults。
    /// ContentView.task 仅作为后备（清理 UserDefaults 残留值）。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        // 在任何 SwiftUI 视图创建前设置 appearance，避免 NSTextView textColor 被 AppKit 覆盖
        // ContentView.task 中的 applyAppearance() 仍保留作为兜底
        let appearanceMode = SettingsModel.shared.appearanceMode
        if let nsAppearance = appearanceMode.nsAppearance {
            NSApp.appearance = nsAppearance
        }

        didFinishLaunching = true
        logger.info("applicationDidFinishLaunching — pendingFile: \(self.pendingOpenFileURL != nil), pendingDir: \(self.pendingOpenDirectoryURL != nil)")

        // 延迟处理，确保 SwiftUI WindowGroup 窗口已创建且 ContentView 已挂载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }

            // 如果没有可见窗口，激活 SwiftUI 创建的隐藏窗口
            if !self.hasVisibleWindows() {
                self.activateFirstHiddenWindow()
            }

            // 注册窗口拖拽：绕过 SwiftUI .onDrop，直接使用 AppKit NSDraggingDestination
            self.installFileDropHandler()

            // 冷启动时主动发送文件/目录打开通知
            // 修复：之前依赖 ContentView.task 通过 UserDefaults 读取，存在时序竞争：
            // ContentView.task 可能晚于 restoreLastLocation 执行，导致欢迎页覆盖待打开文件
            // 现在改为 AppDelegate 统一发送通知，ContentView.task 仅作为极早期后备
            // UserDefaults 是协调点：无论谁先处理，都会清除 key，避免重复打开
            let pendingFilePath = UserDefaults.standard.string(forKey: "pendingOpenFilePath")
            let pendingDirPath = UserDefaults.standard.string(forKey: "pendingOpenDirectoryPath")

            if let filePath = pendingFilePath {
                let url = URL(fileURLWithPath: filePath)
                self.pendingOpenFileURL = nil
                UserDefaults.standard.removeObject(forKey: "pendingOpenFilePath")
                UserDefaults.standard.removeObject(forKey: "pendingOpenDirectoryPath")
                self.logger.info("Cold start: posting .openFile for \(url.path)")
                NotificationCenter.default.post(name: .openFile, object: url)
            } else if let dirPath = pendingDirPath {
                let url = URL(fileURLWithPath: dirPath)
                self.pendingOpenDirectoryURL = nil
                UserDefaults.standard.removeObject(forKey: "pendingOpenFilePath")
                UserDefaults.standard.removeObject(forKey: "pendingOpenDirectoryPath")
                self.logger.info("Cold start: posting .openDirectory for \(url.path)")
                NotificationCenter.default.post(name: .openDirectory, object: url)
            } else {
                // UserDefaults 已被 ContentView.task 清理，说明文件已被极早期后备路径打开
                // 仅清理属性，不再发通知，避免重复打开
                self.pendingOpenFileURL = nil
                self.pendingOpenDirectoryURL = nil
                if SettingsModel.shared.reopenLastLocation {
                    self.logger.info("Cold start: restoring last location")
                    NotificationCenter.default.post(name: .restoreLastLocation, object: nil)
                }
            }
        }
    }

    // MARK: - Dock 点击处理

    /// 用户点击 Dock 图标时调用
    /// 当所有窗口都关闭后点击 Dock 图标，激活隐藏窗口
    /// 根据 reopenLastLocation 设置决定恢复上次位置还是显示欢迎页
    /// 返回 false 阻止 SwiftUI WindowGroup 自动创建新窗口，避免双窗口 bug
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            logger.info("applicationShouldHandleReopen — activating hidden window")
            activateFirstHiddenWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.installFileDropHandler()
                if SettingsModel.shared.reopenLastLocation {
                    NotificationCenter.default.post(name: .restoreLastLocation, object: nil)
                } else {
                    NotificationCenter.default.post(name: .resetToWelcome, object: nil)
                }
            }
        }
        return false
    }

    // MARK: - 窗口级拖拽处理

    /// 在窗口上安装文件拖拽处理器
    /// 完全绕过 SwiftUI .onDrop，直接使用 AppKit NSDraggingDestination
    /// 将 overlay 添加到 themeFrame（contentView.superview），确保在所有子视图之上
    private func installFileDropHandler() {
        for window in NSApp.windows {
            guard window.isVisible,
                  window.canBecomeKey,
                  !(window is NSPanel),
                  let contentView = window.contentView,
                  let themeFrame = contentView.superview else { continue }

            let existing = themeFrame.subviews.first(where: { $0 is FileDropOverlayView })
            if existing != nil { continue }

            let overlay = FileDropOverlayView()
            themeFrame.addSubview(overlay)
            overlay.frame = themeFrame.bounds
            overlay.autoresizingMask = [.width, .height]
            logger.info("FileDropOverlayView installed on theme frame of window '\(window.title)'")
        }
    }
}

// MARK: - 文件拖拽覆盖视图

/// 透明 NSView 覆盖层，直接实现 NSDraggingDestination 处理文件拖拽
///
/// 完全绕过 SwiftUI 的 .onDrop 机制。
/// 安装在窗口 themeFrame 上，位于所有子视图之上。
/// hitTest 始终返回 nil — macOS 拖拽系统通过 registerForDraggedTypes + 视图 frame
/// 独立路由拖拽事件，不依赖 hitTest；返回 nil 确保所有鼠标事件（点击、滚动等）
/// 透传到下层 SwiftUI 视图。
final class FileDropOverlayView: NSView {

    private let logger = Logger(subsystem: "com.markdownreader.app", category: "FileDropOverlay")

    /// 支持的文件扩展名
    private static let supportedExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        logger.info("viewDidMoveToSuperview — superview: \(self.superview != nil ? "yes" : "no"), frame: \(NSStringFromRect(self.frame))")
    }

    override func draw(_ dirtyRect: NSRect) {
    }

    // MARK: - hitTest 策略

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 始终返回 nil：透传所有鼠标事件（点击、滚动）
        // macOS 拖拽系统通过 registerForDraggedTypes + 视图 frame 独立路由拖拽事件
        return nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let canAccept = canAcceptDrag(sender)
        logger.info("draggingEntered — canAccept: \(canAccept)")
        guard canAccept else { return [] }
        NotificationCenter.default.post(name: .dragHoverChanged, object: true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        logger.info("draggingExited")
        NotificationCenter.default.post(name: .dragHoverChanged, object: false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        logger.info("performDragOperation")
        NotificationCenter.default.post(name: .dragHoverChanged, object: false)

        let pasteboard = sender.draggingPasteboard

        let urls: [URL]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            urls = fileURLs
        } else if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
                  !paths.isEmpty {
            urls = paths.map { URL(fileURLWithPath: $0) }
        } else {
            return false
        }

        guard let url = urls.first else { return false }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }

        if isDir.boolValue {
            NotificationCenter.default.post(name: .openDirectory, object: url)
        } else {
            let ext = url.pathExtension.lowercased()
            if Self.supportedExtensions.contains(ext) || ext.isEmpty {
                NotificationCenter.default.post(name: .openFile, object: url)
            } else {
                NotificationCenter.default.post(name: .unsupportedFileTypeDropped, object: ext)
            }
        }
        return true
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    // MARK: - 辅助

    private func canAcceptDrag(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true {
            return true
        }
        return false
    }
}
