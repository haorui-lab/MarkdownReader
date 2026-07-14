import Foundation

/// 显示模式枚举：渲染 / 编辑
public enum DisplayMode: String, CaseIterable, Sendable {
    case rendered = "渲染"
    case raw = "编辑"
}
