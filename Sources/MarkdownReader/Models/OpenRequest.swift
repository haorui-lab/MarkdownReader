import Foundation

/// 一次打开请求的来源与内容。
///
/// `preferredWindowID` 只表达「优先复用此空白窗口」。它不能绕过文件所有权，
/// 也不能强制覆盖已承载资源的窗口。
struct OpenRequest: Sendable {
    enum Source: Sendable {
        case finder
        case commandLine
        case openPanel
        case openRecent
        case dragDrop
        case markdownLink
        case restoreLastLocation
    }

    let urls: [URL]
    let source: Source
    let preferredWindowID: WindowID?

    init(urls: [URL], source: Source, preferredWindowID: WindowID? = nil) {
        self.urls = urls
        self.source = source
        self.preferredWindowID = preferredWindowID
    }
}
