import SwiftUI
import MarkdownReaderKit

/// 管理 About 面板窗口，确保同一时间只有一个 About 窗口
@MainActor
final class AboutWindowController: Sendable {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show(language: Language) {
        // 如果已有 About 窗口，直接前置
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView(language: language)
        let hosting = NSHostingView(rootView: aboutView)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 560)

        let newWindow = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentView = hosting
        newWindow.title = L10n.tr(.aboutTitle, language: language)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)

        window = newWindow
    }
}
