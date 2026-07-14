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

   /// 命令目标：菜单命令经 FocusedValues 路由到此（Task 7）。
   /// 由 session 持有，弱引用自身，session 释放后自动 no-op。
   let commandTarget: WindowCommandTarget

    /// 窗口级 Undo 存储（Task 10）：替代全局 UndoManagerProvider.shared。
    let undoStore = WindowUndoStore()

    /// 注入的资源身份服务，避免每次调用时新建实例。
    private let identityService: ResourceIdentityService

    weak var coordinator: WindowCoordinator?
    weak var window: NSWindow?

    // MARK: - 窗口级状态

    /// 显式空白标记（发现 3：消除派生 isBlank 的竞态窗口）。
    ///
    /// `nil` 表示沿用派生判定（向后兼容）；一旦 open 开始即置为 `false`，
    /// open 失败恢复为 `true`。路由读取 `isBlank` 时优先用显式标记，
    /// 避免 ViewModel 异步刷新过程中三者短暂不一致被路由误判为 blank。
    private var explicitBlankOverride: Bool?

    /// 是否为空白窗口（未打开文件/目录、无 Untitled 待保存文档）。
    var isBlank: Bool {
        if let explicit = explicitBlankOverride {
            return explicit
        }
        return documentViewModel.currentFileURL == nil
            && appViewModel.rootDirectory == nil
            && !documentViewModel.isUntitled
    }

    /// open 操作开始时调用：立即将本窗口标记为非空白，阻止路由在异步加载期间复用它。
    func markOpenStarted() {
        explicitBlankOverride = false
    }

    /// open 操作失败时调用：恢复空白标记，使该窗口仍可被后续打开复用。
    func markOpenFailed() {
        explicitBlankOverride = true
    }

    /// 清除显式标记，回到派生判定（open 成功后 ViewModel 状态已稳定）。
    func clearBlankOverride() {
        explicitBlankOverride = nil
    }

    init(
        id: WindowID,
        settings: SettingsModel = .shared,
        identityService: ResourceIdentityService = ResourceIdentityService(),
        coordinator: WindowCoordinator? = nil
    ) {
        self.id = id
        self.appViewModel = AppViewModel()
        self.fileTreeViewModel = FileTreeViewModel(settings: settings)
        self.documentViewModel = DocumentViewModel(settings: settings)
        self.commandPaletteViewModel = CommandPaletteViewModel()
        self.identityService = identityService
        self.coordinator = coordinator
        self.commandTarget = WindowCommandTarget(session: nil)

        // 连接 ViewModel 间依赖（原 ContentView.task 中的逻辑）
        self.fileTreeViewModel.documentViewModel = documentViewModel
       self.commandPaletteViewModel.configure(
           appViewModel: appViewModel,
           fileTreeViewModel: fileTreeViewModel,
           documentViewModel: documentViewModel,
           settings: settings
       )
       self.commandPaletteViewModel.coordinator = coordinator
       self.commandPaletteViewModel.windowID = id
        self.documentViewModel.undoStore = undoStore

        // commandTarget 弱引用本 session（init 后回填，避免 self 未完成初始化）
        self.commandTarget.session = self

        // Task 9：目录树选择经本 session 路由（所有权冲突时激活 owner，不改本窗口选中项）。
        self.fileTreeViewModel.onSelectFileViaSession = { [weak self] url in
            self?.requestFileSelection(url)
        }
    }

   // MARK: - 资源打开

    /// 通过 OpenPanel 选择文件/目录并在本窗口打开（Task 8）。
    /// 使用窗口级 sheet，不再全局 runModal。
    func openFromPanel() {
        guard let window else { return }
        let language = SettingsModel.shared.languagePref.resolvedLanguage
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let url = await OpenPanelHelper.chooseResource(for: window, language: language) else { return }
            coordinator?.enqueue(OpenRequest(url: url, source: .openPanel, preferredWindowID: self.id))
        }
    }

    /// 在本会话内打开文件资源。
    ///
    /// 调用方需已通过 Coordinator 路由确认本会话是合法 owner。
    /// 所有权声明（claim）由路由成功后的调用点统一负责，不在本方法内重复 claim——
    /// 避免与路由引擎形成双保险且用 `try?` 吞掉冲突（历史 bug）。
    func openFile(_ url: URL) async {
        appViewModel.openSingleFile(url)
        fileTreeViewModel.selectedFileURL = url
        await documentViewModel.loadFile(at: url)
    }

    /// 在本会话内以目录模式打开。
    ///
    /// 同 `openFile`，所有权声明由调用点负责。
    func openDirectory(_ url: URL) async {
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

    // MARK: - 窗口级命令（Task 7：替代无目标通知广播）

    /// 新建未保存文件：脏 Untitled 时先询问是否放弃，再创建。
    /// 注意：未保存确认弹窗需要 UI 上下文，目前直接在脏 Untitled 时跳过创建以避免
    /// 数据丢失；完整确认流程由调用方（菜单/按钮）在视图层处理。此处保留基础语义，
    /// 保证菜单 New File 在焦点窗口生效而不广播。
    func handleNewFile() {
        if documentViewModel.isUntitled && documentViewModel.isDirty {
            // 脏 Untitled：不静默覆盖，交由视图层弹窗后再调 createUntitledFile。
            // 菜单路径下此处直接返回，避免丢失未保存内容。
            return
        }
        guard documentViewModel.createUntitledFile() != nil else { return }
        fileTreeViewModel.selectedFileURL = nil
        appViewModel.selectedFile = nil
        appViewModel.hasUnsavedUntitled = true
        appViewModel.untitledFileName = documentViewModel.fileName
    }

    /// 保存当前文件（含重入保护）。
    func handleSave() {
        guard !documentViewModel.isSaving && !documentViewModel.isSavePanelShowing else { return }
        Task { @MainActor in await documentViewModel.save() }
    }

    /// 另存为：弹 NSSavePanel，成功后迁移所有权并刷新文件树/最近记录。
    func handleSaveAs() {
        guard !documentViewModel.isSavePanelShowing else { return }
        let settings = SettingsModel.shared
        documentViewModel.isSavePanelShowing = true
        let language = settings.languagePref.resolvedLanguage
        let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
        let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

       guard let saveURL = OpenPanelHelper.showSavePanel(
            for: window,
            language: language,
            defaultDirectory: defaultDir,
            suggestedName: suggestedName
       ) else {
            documentViewModel.isSavePanelShowing = false
            return
        }

        let oldURL = documentViewModel.currentFileURL
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.documentViewModel.saveAs(to: saveURL)
            self.appViewModel.hasUnsavedUntitled = false

            // 所有权迁移：旧 URL → 新 URL（仅当旧 URL 由本窗口持有）
            if let oldURL, let coordinator = self.coordinator {
                try? coordinator.migrateOwnership(from: oldURL, to: saveURL, for: self.id)
            }

            if let rootDir = self.appViewModel.rootDirectory,
               saveURL.path.hasPrefix(rootDir.path + "/") {
                await self.fileTreeViewModel.loadDirectory(rootDir)
                self.fileTreeViewModel.selectedFileURL = saveURL
            }

            settings.lastOpenedFile = saveURL
            settings.addRecentItem(url: saveURL, isDirectory: false)
            self.documentViewModel.isSavePanelShowing = false
        }
    }
}

// MARK: - CloseDecision

/// 单窗口关闭决策。
enum CloseDecision: Equatable, Sendable {
    case close
    case needsUntitledDecision
    case cancel
}
