import SwiftUI

/// 窗口场景宿主（Task 6）。
///
/// data-driven `WindowGroup(for: WindowID.self)` 的内容视图。每个窗口绑定一个
/// `WindowID`，由 `WindowSceneHost` 创建对应 `WindowSession` 注入 `ContentView`，
/// 并通过 `WindowLifecycleBridge` 把生命周期接到 `WindowCoordinator`。
///
/// `WindowSession` 弱引用 Coordinator，强引用窗口级 ViewModel；Coordinator 在注册期间
/// 强持有 session（见设计文档 §7.1 引用关系）。
struct WindowSceneHost: View {
    let windowID: WindowID
    let coordinator: WindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var session: WindowSession

    init(windowID: WindowID, coordinator: WindowCoordinator) {
        self.windowID = windowID
        self.coordinator = coordinator
        _session = State(initialValue: WindowSession(
            id: windowID,
            coordinator: coordinator
        ))
    }

    var body: some View {
        ContentView(session: session)
            .background(WindowLifecycleBridge(session: session))
            .task {
                // 安装 OpenWindowAction，使 Coordinator 可创建新窗口（幂等）
                coordinator.install(openWindowAction: openWindow)
                // 注册 session（window 在 bridge 挂载时回填并 attach）
                coordinator.register(session: session)
                // 消费预存资源（新窗口为某文件而创建时）
                if let resource = coordinator.consumePendingResource(for: windowID) {
                    await open(resource: resource)
                }
            }
    }

    /// 消费预存资源：把 pending resource 转成 URL 并在本会话打开。
    @MainActor
    private func open(resource: ResourceIdentity) async {
        let url = resource.canonicalURL
        // 声明所有权（路由成功后由本调用点统一负责，见 WindowSession.openFile 注释）
        try? coordinator.claim(resource, for: windowID)
        session.markOpenStarted()
        await session.openFile(url)
        session.clearBlankOverride()
    }
}
