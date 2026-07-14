import SwiftUI
import AppKit

/// 窗口生命周期桥接器（Task 6）。
///
/// 以 0 尺寸 NSViewRepresentable 挂在 ContentView 背景，负责：
/// 1. 窗口挂载时把真实 `NSWindow` 回填给 `session.window`，并通知 Coordinator 关联；
/// 2. 窗口即将关闭时调用 `session.dispose()`，释放所有权与注册项。
///
/// 不依赖 NSWindowDelegate 的 `windowWillClose`（已有 `WindowCloseGuard` 占用代理），
/// 而是用 `NSWindow.willCloseNotification` 观察具体窗口，避免代理冲突。
struct WindowLifecycleBridge: View {
    let session: WindowSession

    var body: some View {
        LifecycleAnchor(session: session)
            .frame(width: 0, height: 0)
    }
}

private struct LifecycleAnchor: NSViewRepresentable {
    let session: WindowSession

    func makeNSView(context: Context) -> NSView {
        let view = LifecycleAnchorView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? LifecycleAnchorView)?.session = session
    }

    private final class LifecycleAnchorView: NSView {
        weak var session: WindowSession?
        // 观察者注册表。viewDidMoveToWindow 每次切换窗口时先清空旧观察者，
        // 不依赖 deinit 清理（Swift 6 下非 Sendable 属性不可在 deinit 中访问）。
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 离开旧窗口：同步移除观察者
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()

            guard let window, let session else { return }

           // 1. 回填 NSWindow 给 session，并通知 Coordinator 关联窗口
           session.window = window
           session.coordinator?.attach(window: window, to: session.id)

            // Task 10：绑定 undoStore 到 NSWindow，使 swizzled getter 无需全局状态
            window.undoStore = session.undoStore

            // 2. 观察该窗口关闭，触发 dispose
            let close = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.session?.dispose() }
            }
            observers = [close]
        }
    }
}
