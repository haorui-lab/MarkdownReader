import Foundation

/// 窗口的稳定唯一身份。
///
/// 只表示窗口身份，不携带文件路径。文件被另存为、重命名或窗口从空白切换到目录时，
/// 窗口身份不改变。这样 SwiftUI `WindowGroup(for: WindowID.self)` 可以稳定地
/// 复用、前置或重建某个具体窗口。
struct WindowID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// SwiftUI `WindowGroup` 的 scene 标识。
enum WindowSceneID {
    static let document = "document-window"
}
