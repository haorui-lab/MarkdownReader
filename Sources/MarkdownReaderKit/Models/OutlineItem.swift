import Foundation

/// Markdown 文档大纲项，表示一个标题条目
public struct OutlineItem: Identifiable, Equatable {
    /// 唯一标识
    public let id = UUID()
    /// 标题层级（1~6 对应 # ~ ######）
    public let level: Int
    /// 标题文本（去除 # 前缀后的纯文本）
    public let title: String
    /// 在原文中的行号（0-based），用于定位滚动
    public let lineNumber: Int
}
