import Foundation
import AppKit
import SwiftUI
import MarkdownReaderKit

/// 窗口会话：单个主窗口的业务边界。
///
/// 统一持有目前分散在 `ContentView` 中的窗口级对象，使每个窗口拥有独立的
/// 浏览、文档、编辑和视图状态。`WindowSession` 弱引用 `WindowCoordinator`，
/// 避免与 Coordinator 形成引用环（设计文档 §7.1）。
@MainActor
@Observable
final class WindowSession {

    // MARK: - 身份与依赖

    let id: WindowID

    let appViewModel: AppViewModel
    let fileTreeViewModel: FileTreeViewModel
    let documentViewModel: DocumentViewModel
    let commandPaletteViewModel: CommandPaletteViewModel

    weak var coordinator: WindowCoordinator?
    weak var window: NSWindow?

    // MARK: - 窗口级状态

    /// 是否为空白窗口（未打开文件/目录、无 Untitled 待保存文档）。
    var isBlank: Bool {
        documentViewModel.currentFileURL == nil
            && appViewModel.rootDirectory == nil
            && !documentViewModel.isUntitled
    }

    init(
        id: WindowID,
        settings: SettingsModel = .shared,
        coordinator: WindowCoordinator? = nil
    ) {
        self.id = id
        self.appViewModel = AppViewModel()
        self.fileTreeViewModel = FileTreeViewModel(settings: settings)
        self.documentViewModel = DocumentViewModel(settings: settings)
        self.commandPaletteViewModel = CommandPaletteViewModel()
        self.coordinator = coordinator

        // 连接 ViewModel 间依赖（原 ContentView.task 中的逻辑）
        self.fileTreeViewModel.documentViewModel = documentViewModel
        self.commandPaletteViewModel.configure(
            appViewModel: appViewModel,
            fileTreeViewModel: fileTreeViewModel,
            documentViewModel: documentViewModel,
            settings: settings
        )
    }

    // MARK: - 资源打开

    /// 在本会话内打开文件资源。
    /// 调用方需已通过 Coordinator 路由确认本会话是合法 owner。
    func openFile(_ url: URL) async {
        let identity = ResourceIdentityService().identity(for: url, kind: .file)
        try? coordinator?.claim(identity, for: id)

        appViewModel.openSingleFile(url)
        fileTreeViewModel.selectedFileURL = url
        await documentViewModel.loadFile(at: url)
    }

    /// 在本会话内以目录模式打开。
    func openDirectory(_ url: URL) async {
        let identity = ResourceIdentityService().identity(for: url, kind: .directory)
        try? coordinator?.claim(identity, for: id)

        appViewModel.openDirectory(url)
        await fileTreeViewModel.loadDirectory(url)
    }

    // MARK: - 目录树选择前路由

    /// 用户在目录树点击文件前的路由。
    /// 若文件已被其他窗口持有，**不修改** selectedFileURL，激活 owner 窗口。
    func requestFileSelection(_ url: URL) {
        guard let coordinator else {
            // 无 coordinator 时回退为直接选择（兼容旧测试/单窗口）
            fileTreeViewModel.selectedFileURL = url
            return
        }

        let decision = coordinator.routeFileSelection(url, from: id)
        switch decision {
        case .openInSession:
            fileTreeViewModel.selectedFileURL = url
        case .activateOwner(let ownerID, _):
            // 关键约束：不修改 selectedFileURL，避免抢先加载造成双所有权。
            coordinator.activate(windowID: ownerID)
        case .createWindow(let newID, let resource):
            // 目录窗口已承载目录 → 为该文件创建新窗口（理论上目录树内导航不应触发，
            // 但保留分支以防空白窗口误用）。
            coordinator.openResourceInNewWindow(resource)
            _ = newID
        case .reject:
            break
        }
    }

    // MARK: - 关闭决策

    /// 判断关闭本窗口是否需要 Untitled 保存确认。
    func prepareForClose() -> CloseDecision {
        if documentViewModel.isUntitled && documentViewModel.isDirty {
            return .needsUntitledDecision
        }
        return .close
    }

    /// 释放本会话全部状态：所有权、文件监控、observer 等。
    /// 由 WindowLifecycleBridge.windowWillClose 调用。
    func dispose() {
        coordinator?.unregister(windowID: id)
    }
}

// MARK: - CloseDecision

/// 单窗口关闭决策。
enum CloseDecision: Equatable, Sendable {
    case close
    case needsUntitledDecision
    case cancel
}
