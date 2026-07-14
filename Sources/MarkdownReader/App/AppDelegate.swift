import SwiftUI
import MarkdownReaderKit
import os

/// 应用委托，处理 macOS 应用生命周期事件。
///
/// Task 8：所有文件/目录打开入口统一通过 `WindowCoordinator.enqueue(OpenRequest)` 路由。
/// 冷启动时 Coordinator 尚未 attach 窗口，请求在内存队列暂存；attach 后 drain。
/// 已删除：pendingOpenFileURL/pendingOpenDirectoryURL UserDefaults、0.5s 启动延迟、
/// 单窗口守卫（Task 6 已删）、activateFirstHiddenWindow 通知广播。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.markdownreader.app", category: "AppDelegate")

    /// 应用是否已经完成启动
    private var didFinishLaunching = false

    /// 应用即将完成启动
    func applicationWillFinishLaunching(_ notification: Notification) {
        logger.info("applicationWillFinishLaunching")
    }

    // MARK: - 文件打开回调

    /// macOS 13+ URL 版本的文件打开回调。
    /// 冷启动时在 applicationDidFinishLaunching 之前调用；热启动时直接调用。
    /// 传递完整 URL 列表给 Coordinator，不再截断为单个 URL，不再写 UserDefaults。
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("application(_:open:) called with \(urls.count) URLs")
        guard !urls.isEmpty else { return }

        // 构造 OpenRequest 并入队。Coordinator 在 ready 前暂存，ready 后立即处理。
        let request = OpenRequest(urls: urls, source: .external)
        enqueueRequest(request)
    }

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        let appearanceMode = SettingsModel.shared.appearanceMode
        if let nsAppearance = appearanceMode.nsAppearance {
            NSApp.appearance = nsAppearance
        }

        didFinishLaunching = true
        logger.info("applicationDidFinishLaunching")

        // 注册窗口拖拽
        installFileDropHandler()

        // 冷启动无 pending 外部文件时恢复上次位置
        // external 请求已在 application(_:open:) 中入队，Coordinator 会优先处理它们
        let coordinator = Self.coordinator
        if coordinator.pendingRequestCount == 0 {
            if SettingsModel.shared.reopenLastLocation {
                logger.info("Cold start: restoring last location")
                NotificationCenter.default.post(name: .restoreLastLocation, object: nil)
            }
        } else {
            // 有 pending 请求：drain，external 优先
            coordinator.drainPendingRequests()
        }
    }

    // MARK: - Dock 点击处理

    /// 用户点击 Dock 图标时调用。
    /// 无可见窗口时创建空白窗口（通过 Coordinator），不再激活隐藏窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            logger.info("applicationShouldHandleReopen — no visible windows")
            let coordinator = Self.coordinator
            if coordinator.hasRegisteredSession {
                // 有注册但不可见的窗口：激活最后一个
                if let lastID = coordinator.lastActiveWindowID {
                    coordinator.activate(windowID: lastID)
                }
            } else {
                // 无任何窗口：创建空白窗口
                coordinator.openBlankWindow()
            }
            installFileDropHandler()
        }
        return false
    }

    // MARK: - 窗口级拖拽处理

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

    // MARK: - Coordinator 访问

    /// AppDelegate 通过此属性访问 App 持有的 WindowCoordinator。
    /// MarkdownReaderApp 在 init 时注入。
    static var coordinator: WindowCoordinator {
        _sharedCoordinator
    }

    private static let _sharedCoordinator = WindowCoordinator()

    /// 将打开请求入队到 Coordinator。
    /// 冷启动（didFinishLaunching == false）时仅入队，等 applicationDidFinishLaunching drain。
    /// 热启动时 Coordinator 已 ready，立即处理。
    private func enqueueRequest(_ request: OpenRequest) {
        let coordinator = Self.coordinator
        if didFinishLaunching && coordinator.hasRegisteredSession {
            coordinator.drainPendingRequests()
            coordinator.enqueue(request)
        } else {
            coordinator.enqueue(request)
        }
    }
}

// MARK: - 文件拖拽覆盖视图

/// 透明 NSView 覆盖层，直接实现 NSDraggingDestination 处理文件拖拽。
///
/// Task 8：拖拽打开改为构造 OpenRequest 并通过 Coordinator 路由。
final class FileDropOverlayView: NSView {

    private let logger = Logger(subsystem: "com.markdownreader.app", category: "FileDropOverlay")

    private static let supportedExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    override func draw(_ dirtyRect: NSRect) {}

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let canAccept = canAcceptDrag(sender)
        guard canAccept else { return [] }
        NotificationCenter.default.post(name: .dragHoverChanged, object: true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        NotificationCenter.default.post(name: .dragHoverChanged, object: false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
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

        guard !urls.isEmpty else { return false }

        // Task 8：通过 Coordinator 统一路由拖拽打开的 URL
        let request = OpenRequest(urls: urls, source: .dragDrop)
        AppDelegate.coordinator.enqueue(request)
        return true
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

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
