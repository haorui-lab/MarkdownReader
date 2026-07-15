import Foundation

/// 单个窗口会话的路由快照（纯值，供路由引擎读取）。
struct SessionRoutingSnapshot: Equatable, Sendable {
    let id: WindowID
    var isBlank: Bool
}

/// 路由引擎读取的当前路由状态快照。
/// 包含所有会话的空白标记和资源所有权映射。
struct WindowRoutingState: Sendable {
    var sessions: [WindowID: SessionRoutingSnapshot] = [:]
    var owners: [ResourceIdentity: WindowID] = [:]

    static let empty = WindowRoutingState()
}

/// 纯路由引擎。
///
/// 只读取 `WindowRoutingState` 并返回 `RouteDecision`，不调用任何 AppKit/SwiftUI。
/// 决策顺序固定：
///
/// 1. owner → 资源已被持有，激活所有者窗口。
/// 2. preferred blank → 优先复用指定空白窗口。
/// 3. 任意可复用 blank → 复用任意空白窗口。
/// 4. create window → 创建新窗口。
struct WindowRoutingEngine: Sendable {

    /// 对单个资源做决策。
    func decision(
        for resource: ResourceIdentity,
        preferredWindowID: WindowID?,
        state: WindowRoutingState,
        makeWindowID: () -> WindowID = { WindowID() }
    ) -> RouteDecision {
        // 1. 已有 owner：激活 owner，不重分配。
        if let owner = state.owners[resource] {
            return .activateOwner(owner, resource)
        }

        // 2. preferred 是空白窗口：复用。
        if let preferred = preferredWindowID,
           let snapshot = state.sessions[preferred],
           snapshot.isBlank {
            return .openInSession(preferred, resource)
        }

        // 3. 任意空白窗口：复用第一个（按稳定顺序）。
        if let blank = firstBlankSession(in: state) {
            return .openInSession(blank, resource)
        }

        // 4. 创建新窗口。
        return .createWindow(makeWindowID(), resource)
    }

    /// 对一批资源（来自同一次 `OpenRequest`）做决策。
    /// 归一化后的重复资源只处理一次；多个新资源按输入顺序复用一个空白窗口，其余各自建窗。
    func decisions(
        for resources: [ResourceIdentity],
        preferredWindowID: WindowID?,
        state: WindowRoutingState,
        makeWindowID: () -> WindowID = { WindowID() }
    ) -> [RouteDecision] {
        // 决策过程中需要累加「已用空白窗口」和「新建的 owner」，避免一批请求里
        // 重复复用同一空白窗口。这里维护一个可变副本。
        var working = state
        var seen = Set<ResourceIdentity>()
        var results: [RouteDecision] = []
        var blankConsumed: WindowID? = nil

        for resource in resources {
            guard !seen.contains(resource) else { continue }
            seen.insert(resource)

            // 已有 owner（含本批刚创建/占用的）→ 激活。
            if let owner = working.owners[resource] {
                results.append(.activateOwner(owner, resource))
                continue
            }

            // 复用空白窗口：优先 preferred，再任意 blank，且整批只复用一个空白窗口。
            if blankConsumed == nil {
                if let preferred = preferredWindowID,
                   let snapshot = working.sessions[preferred],
                   snapshot.isBlank {
                    working.owners[resource] = preferred
                    working.sessions[preferred] = SessionRoutingSnapshot(id: preferred, isBlank: false)
                    blankConsumed = preferred
                    results.append(.openInSession(preferred, resource))
                    continue
                }
                if let blank = firstBlankSession(in: working) {
                    working.owners[resource] = blank
                    working.sessions[blank] = SessionRoutingSnapshot(id: blank, isBlank: false)
                    blankConsumed = blank
                    results.append(.openInSession(blank, resource))
                    continue
                }
            }

            // 创建新窗口。
            let newID = makeWindowID()
            working.owners[resource] = newID
            working.sessions[newID] = SessionRoutingSnapshot(id: newID, isBlank: false)
            results.append(.createWindow(newID, resource))
        }

        return results
    }

    /// 取第一个空白会话。按 WindowID 的稳定顺序遍历，避免随机性。
    private func firstBlankSession(in state: WindowRoutingState) -> WindowID? {
        state.sessions
            .values
            .filter { $0.isBlank }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            .first?
            .id
    }
}
