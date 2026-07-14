import Foundation

/// 资源打开失败的错误类型。
enum OpenRoutingError: LocalizedError, Equatable, Sendable {
    case resourceMissing(URL)
    case unsupportedType(URL)
    case ownershipConflict(URL, owner: WindowID)
    case ownershipMigrationConflict(URL, owner: WindowID)
    case windowCreationFailed

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let url):
            return "资源不存在：\(url.path)"
        case .unsupportedType(let url):
            return "不支持的文件类型：\(url.lastPathComponent)"
        case .ownershipConflict(let url, _):
            return "该文件已在另一窗口中打开：\(url.lastPathComponent)"
        case .ownershipMigrationConflict(let url, _):
            return "另存为目标已在另一窗口中打开：\(url.lastPathComponent)"
        case .windowCreationFailed:
            return "无法创建窗口"
        }
    }
}

/// 路由引擎对单个资源的决策结果。
///
/// 决策应保持为纯逻辑，AppKit/SwiftUI 副作用在决策之后执行，便于单元测试。
enum RouteDecision: Equatable, Sendable {
    /// 在已有窗口会话内打开（复用空白窗口）。
    case openInSession(WindowID, ResourceIdentity)
    /// 创建新窗口打开。
    case createWindow(WindowID, ResourceIdentity)
    /// 资源已被某窗口持有，激活该所有者窗口。
    case activateOwner(WindowID, ResourceIdentity)
    /// 打开失败。
    case reject(OpenRoutingError)
}
