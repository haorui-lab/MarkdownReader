import Foundation
import AppKit
import SwiftUI

/// 应用级窗口协调器。
///
/// 维护会话注册表和资源所有权注册表，将无副作用的路由判断委托给 `WindowRoutingEngine`。
/// 所有写入都在 `@MainActor` 完成，保证所有权事务原子性。
///
/// 引用关系（见设计文档 §7.1）：
/// - App 持有 Coordinator。
/// - Coordinator 在窗口注册期间强持有 `WindowSession`（通过 sessions 字典）。
/// - `WindowSession` 弱引用 Coordinator，避免环。
/// - Coordinator 只弱持有 `NSWindow`。
@MainActor
@Observable
final class WindowCoordinator {

    // MARK: - 注册表

    /// 已注册会话：windowID → session。强持有真实会话；测试占位时不写入此字典。
    private(set) var sessions: [WindowID: WindowSession] = [:]

    /// 已注册的 windowID 集合（含测试占位，用于区分「注册」与「未注册」）。
    private var registeredIDs: Set<WindowID> = []

    /// 资源所有权：identity → windowID。
    private(set) var resourceOwners: [ResourceIdentity: WindowID] = [:]

    /// 每个窗口持有的资源集合（反向索引，便于注销时批量释放）。
    private var ownedResources: [WindowID: Set<ResourceIdentity>] = [:]

    /// 测试用 registerSession 的空白标记。真实 session 通过 WindowSession.isBlank 计算。
    private var blankFlags: [WindowID: Bool] = [:]

    /// 待加载资源：windowID → resource。用于新窗口创建后取走初始资源。
    private var pendingResources: [WindowID: ResourceIdentity] = [:]

    /// 弱持有 NSWindow，用于激活/前置。
    private var windows: [WindowID: WeakWindow] = [:]

    /// 最后活动窗口，用于 Dock 重开前置和单窗口恢复。
    private(set) var lastActiveWindowID: WindowID?

    // MARK: - 依赖

    private let identityService: ResourceIdentityService
    private let routingEngine: WindowRoutingEngine
    private var openWindowAction: OpenWindowAction?

    init(
        identityService: ResourceIdentityService = ResourceIdentityService(),
        routingEngine: WindowRoutingEngine = WindowRoutingEngine()
    ) {
        self.identityService = identityService
        self.routingEngine = routingEngine
    }

    // MARK: - 注册表查询

    var sessionCount: Int { registeredIDs.count }

    /// id 是否已注册（含真实 session 或测试占位）。
    func isRegistered(_ id: WindowID) -> Bool { registeredIDs.contains(id) }

    func owner(of identity: ResourceIdentity) -> WindowID? { resourceOwners[identity] }

    func ownerWindowID(ofFile url: URL) -> WindowID? {
        let identity = identityService.identity(for: url, kind: .file)
        return resourceOwners[identity]
    }

    /// 当前是否存在任何空白会话。
    var hasBlankSession: Bool {
        registeredIDs.contains { id in
            sessions[id]?.isBlank ?? (blankFlags[id] ?? false)
        }
    }

    /// 当前是否已注册至少一个会话。
    var hasRegisteredSession: Bool { !registeredIDs.isEmpty }

    // MARK: - OpenWindowAction 安装

    /// 安装 SwiftUI 的 `OpenWindowAction`，使 Coordinator 能创建新窗口。
    /// 幂等：可多次调用，只保留最新 action。
    func install(openWindowAction: OpenWindowAction) {
        self.openWindowAction = openWindowAction
    }

    var isReady: Bool { openWindowAction != nil }

    // MARK: - 会话注册

    /// 注册会话。Coordinator 强持有 session。
    func register(session: WindowSession) {
        sessions[session.id] = session
        registeredIDs.insert(session.id)
        if ownedResources[session.id] == nil {
            ownedResources[session.id] = []
        }
    }

    /// 注册会话的轻量重载（测试用，不依赖真实 session 对象，仅维护路由快照）。
    func registerSession(id: WindowID, isBlank: Bool) {
        if ownedResources[id] == nil { ownedResources[id] = [] }
        registeredIDs.insert(id)
        blankFlags[id] = isBlank
    }

    /// 关联 NSWindow 到 windowID（弱引用）。
    func attach(window: NSWindow, to windowID: WindowID) {
        windows[windowID] = WeakWindow(value: window)
    }

    /// 注销会话：释放 session、窗口引用和所有资源所有权。
    func unregister(windowID: WindowID) {
        // 释放该窗口持有的全部资源所有权
        if let resources = ownedResources.removeValue(forKey: windowID) {
            for resource in resources {
                if resourceOwners[resource] == windowID {
                    resourceOwners.removeValue(forKey: resource)
                }
            }
        }
        pendingResources.removeValue(forKey: windowID)
        windows.removeValue(forKey: windowID)
        blankFlags.removeValue(forKey: windowID)
        registeredIDs.remove(windowID)
        sessions.removeValue(forKey: windowID)
        if lastActiveWindowID == windowID {
            lastActiveWindowID = registeredIDs.first
        }
    }

    // MARK: - 所有权事务

    /// 声明某窗口持有某资源。
    /// - Throws: 资源已被其他窗口持有时抛 `ownershipConflict`。
    func claim(_ resource: ResourceIdentity, for windowID: WindowID) throws {
        if let existing = resourceOwners[resource], existing != windowID {
            throw OpenRoutingError.ownershipConflict(resource.canonicalURL, owner: existing)
        }
        resourceOwners[resource] = windowID
        ownedResources[windowID, default: []].insert(resource)
    }

    /// 释放某窗口对某资源的所有权。
    func release(_ resource: ResourceIdentity, for windowID: WindowID) {
        guard resourceOwners[resource] == windowID else { return }
        resourceOwners.removeValue(forKey: resource)
        ownedResources[windowID]?.remove(resource)
    }

    /// 原子迁移所有权：旧 URL → 新 URL（用于另存为/重命名/移动）。
    /// - 先预检目标是否已被其他窗口持有。
    /// - 旧所有权必须属于本窗口。
    /// - 任一步失败不得修改原状态。
    func migrateOwnership(from oldURL: URL, to newURL: URL, for windowID: WindowID) throws {
        let oldIdentity = identityService.identity(for: oldURL, kind: .file)
        let newIdentity = identityService.identity(for: newURL, kind: .file)

        // 旧 URL 必须由本窗口持有
        guard resourceOwners[oldIdentity] == windowID else {
            // 旧所有权不属于本窗口：无操作（保存到新位置但不迁移不冲突）
            // 仍需检查新目标是否被他人占用
            if let other = resourceOwners[newIdentity], other != windowID {
                throw OpenRoutingError.ownershipMigrationConflict(newURL, owner: other)
            }
            try claim(newIdentity, for: windowID)
            return
        }

        // 新目标已被其他窗口持有 → 冲突，不修改任何状态
        if let other = resourceOwners[newIdentity], other != windowID {
            throw OpenRoutingError.ownershipMigrationConflict(newURL, owner: other)
        }

        // 执行迁移
        resourceOwners.removeValue(forKey: oldIdentity)
        ownedResources[windowID]?.remove(oldIdentity)
        resourceOwners[newIdentity] = windowID
        ownedResources[windowID, default: []].insert(newIdentity)
    }

    // MARK: - 待加载资源

    /// 为待创建窗口预存初始资源。
    func storePending(resource: ResourceIdentity, for windowID: WindowID) {
        pendingResources[windowID] = resource
    }

    /// 取走并清除该窗口的待加载资源。
    func consumePendingResource(for windowID: WindowID) -> ResourceIdentity? {
        pendingResources.removeValue(forKey: windowID)
    }

    // MARK: - 路由

    /// 目录树/命令面板点击文件前的路由判断。
    func routeFileSelection(_ url: URL, from windowID: WindowID) -> RouteDecision {
        let resource = identityService.identity(for: url, kind: .file)
        let state = routingSnapshot()
        return routingEngine.decision(
            for: resource,
            preferredWindowID: windowID,
            state: state
        )
    }

    /// 构造路由引擎所需的状态快照。
    func routingSnapshot() -> WindowRoutingState {
        var state = WindowRoutingState()
        for id in registeredIDs {
            let blank = sessions[id]?.isBlank ?? (blankFlags[id] ?? false)
            state.sessions[id] = SessionRoutingSnapshot(id: id, isBlank: blank)
        }
        state.owners = resourceOwners
        return state
    }

    // MARK: - 窗口创建与激活

    /// 创建一个空白窗口。
    func openBlankWindow() {
        let id = WindowID()
        openWindowAction?(id: WindowSceneID.document, value: id)
    }

    /// 为指定资源创建窗口，并预存初始资源供新窗口消费。
    func openResourceInNewWindow(_ resource: ResourceIdentity) {
        let id = WindowID()
        storePending(resource: resource, for: id)
        openWindowAction?(id: WindowSceneID.document, value: id)
    }

    /// 激活某窗口：解最小化、显示、置前、激活应用。
    func activate(windowID: WindowID) {
        lastActiveWindowID = windowID
        guard let window = windows[windowID]?.value else {
            // 窗口引用失效：通过 openWindow 重建/前置
            openWindowAction?(id: WindowSceneID.document, value: windowID)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window.deminiaturize(nil)
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 记录最后活动窗口。
    func recordActive(windowID: WindowID) {
        lastActiveWindowID = windowID
    }

    /// 所有已注册且仍可见的窗口（用于 Dock 重开判断和 Window 菜单）。
    func visibleWindowIDs() -> [WindowID] {
        registeredIDs.filter { id in
            windows[id]?.value?.isVisible == true
        }
    }
}

// MARK: - WeakWindow

/// 弱引用 NSWindow 的包装，避免 Coordinator 与窗口形成引用环。
struct WeakWindow {
    weak var value: NSWindow?
    init(value: NSWindow?) { self.value = value }
}
