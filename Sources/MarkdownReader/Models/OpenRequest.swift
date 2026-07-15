import Foundation

/// 文件打开请求的来源。用于区分不同入口，以便路由和日志追踪。
enum OpenRequestSource: Sendable, Equatable {
    case external          // Finder 双击 / `open` 命令 / URL scheme
    case openRecent        // 「打开最近」菜单
    case openPanel         // Cmd+O 打开面板
    case commandPalette    // 命令面板
    case dragDrop          // 拖拽到窗口
    case linkedFile        // 渲染页内链接点击
}

/// 统一的资源打开请求。
///
/// 所有文件/目录打开入口（Finder、Open Recent、OpenPanel、命令面板、拖拽、链接点击）
/// 都构造为 `OpenRequest` 并通过 `WindowCoordinator.enqueue` 提交，由 Coordinator 统一路由。
/// 冷启动时 Coordinator 尚未 attach 窗口，请求在内存队列暂存；attach 后一次性 drain。
struct OpenRequest: Sendable, Equatable {
    let urls: [URL]
    let source: OpenRequestSource
    /// 发起请求的窗口（若适用）。用于路由引擎的 preferred blank 复用。
    let preferredWindowID: WindowID?

    init(urls: [URL], source: OpenRequestSource, preferredWindowID: WindowID? = nil) {
        self.urls = urls
        self.source = source
        self.preferredWindowID = preferredWindowID
    }

    init(url: URL, source: OpenRequestSource, preferredWindowID: WindowID? = nil) {
        self.urls = [url]
        self.source = source
        self.preferredWindowID = preferredWindowID
    }
}
