import SwiftUI
import MarkdownReaderKit

/// 自定义红绿灯按钮（关闭/最小化/最大化），替代系统红绿灯以实现位置控制
struct TrafficLightButtons: View {
    /// 是否显示图标（hover 时显示）
    @State private var isHovering = false

    /// 按钮间距
    private let spacing: CGFloat = 8

    /// 按钮直径
    private let buttonSize: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            // 关闭按钮
            trafficLightButton(
                color: Color(nsColor: .systemRed),
                icon: "xmark",
                action: closeWindow
            )

            // 最小化按钮
            trafficLightButton(
                color: Color(nsColor: .systemYellow),
                icon: "minus",
                action: miniaturizeWindow
            )

            // 最大化按钮
            trafficLightButton(
                color: Color(nsColor: .systemGreen),
                icon: "plus",
                action: zoomWindow
            )
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - 按钮组件

    private func trafficLightButton(
        color: Color,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: buttonSize, height: buttonSize)

                if isHovering {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize)
    }

    // MARK: - 窗口操作

    /// Task 11：红绿灯操作必须作用于它所属的窗口。
    /// SwiftUI 视图无直接 NSView 句柄，但按钮可点击意味着其所在窗口已成为 key（AppKit 点击会先
    /// makeKeyAndOrderFront）。因此 NSApp.keyWindow 在红绿灯点击时就是本窗口，无需依赖焦点路由。
    /// 保留 performClose 以触发 NSWindowDelegate.windowShouldClose（未保存更改提醒）。
    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    private func miniaturizeWindow() {
        NSApp.keyWindow?.miniaturize(nil)
    }

    private func zoomWindow() {
        NSApp.keyWindow?.zoom(nil)
    }
}
