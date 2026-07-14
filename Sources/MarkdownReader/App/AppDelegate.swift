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

    /// 应用级终止协调器（Task 12）
    let terminationCoordinator = ApplicationTerminationCoordinator()

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

        // 注册窗口拖拽：Task 11 起由 WindowLifecycleBridge 在每窗口挂载时安装
        // 窗口级 WindowDropOverlayView，不再由 AppDelegate 全局安装。

        // Task 13：启动优先级由 AppStartupCoordinator 统一裁决。
        // 设置 hasPendingExternalRequests，供 shouldRestoreLastLocation 判断。
        let coordinator = Self.coordinator
        AppStartupCoordinator.shared.hasPendingExternalRequests = coordinator.pendingRequestCount > 0
        if coordinator.pendingRequestCount == 0 {
            // 无外部请求：恢复上次位置（若开启）
            if AppStartupCoordinator.shared.shouldRestoreLastLocation() {
                logger.info("Cold start: restoring last location")
                NotificationCenter.default.post(name: .restoreLastLocation, object: nil)
            }
        } else {
            // 有 pending 请求：drain，external 优先（不恢复上次位置）
            coordinator.drainPendingRequests()
        }
    }

    // MARK: - Dock 点击处理

    /// 用户点击 Dock 图标时调用。
    /// 无可见窗口时创建空白窗口（通过 Coordinator），不再激活隐藏窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            logger.info("applicationShouldHandleReopen — no visible windows")
            terminationCoordinator.handleReopen()
        }
        return false
    }

    // MARK: - 应用退出

    /// Task 12：返回 .terminateLater，由 TerminationCoordinator 串行处理脏 Untitled session。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationCoordinator.coordinator = Self.coordinator
        DispatchQueue.main.async { [weak self] in
            self?.terminationCoordinator.processTermination()
        }
        return .terminateLater
    }

    // MARK: - Coordinator 访问

    /// AppDelegate 通过此属性访问 App 持有的 WindowCoordinator。
    /// MarkdownReaderApp 在 init 时注入。
    static var coordinator: WindowCoordinator {
        _sharedCoordinator
    }

    private static let _sharedCoordinator = WindowCoordinator()

    override init() {
        super.init()
        terminationCoordinator.coordinator = Self._sharedCoordinator
    }

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
