import SwiftUI
import MarkdownReaderKit

/// 主视图，管理自定义 HStack 两列布局
/// 设置模式下左侧显示设置菜单，右侧显示设置内容
///
/// 每个窗口通过 `WindowSession` 注入窗口级业务对象（Task 5 Step 4）。
/// `ContentView` 不再自行创建 ViewModel，而是从 session 派生，保证
/// 多窗口下各窗口拥有独立的文件、目录、编辑、命令面板状态。
struct ContentView: View {
    /// 本窗口的会话边界（由 WindowSceneHost/WindowGroup 注入）。
    let session: WindowSession

    /// 从 session 派生的窗口级 ViewModel，保持原有调用点不变。
    private var appViewModel: AppViewModel { session.appViewModel }
    private var fileTreeViewModel: FileTreeViewModel { session.fileTreeViewModel }
    private var documentViewModel: DocumentViewModel { session.documentViewModel }
    private var commandPaletteViewModel: CommandPaletteViewModel { session.commandPaletteViewModel }

    @State private var settings = SettingsModel.shared
    @Environment(\.language) private var language
    @Environment(\.colorScheme) private var colorScheme

    /// 缓存的主题颜色，避免每次 body 求值时重复执行 NSColor 色彩空间转换和混合运算
    /// 通过 .onChange(of: settings.resolvedTheme) 响应式更新
    @State private var themeColors: ThemeColors = ThemeColors.from(
        SettingsModel.shared.resolvedTheme
    )

    var body: some View {
        mainLayout
            .frame(minWidth: 650, minHeight: 450)
            .ignoresSafeArea()
            .background(themeColors.surface)
            .navigationTitle(appViewModel.windowTitle)
            .environment(\.language, settings.languagePref.resolvedLanguage)
            .applyThemeColors(themeColors)
            .tint(themeColors.accent)
            .modifier(FullScreenStateModifier(appViewModel: appViewModel))
            // Task 7：toggleSidebar / switchDisplayMode 等窗口级命令已迁移到
            // FocusedValues（WindowCommandTarget），不再经通知广播。KeyboardShortcutModifier
            // 中的对应监听已移除，此处保留空 modifier 占位以最小化改动。
            .modifier(FileOpenModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings,
                session: session
            ))
            .modifier(DirectoryChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel
            ))
            .modifier(SelectionChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings
            ))
            .modifier(SettingsChangeModifier(
                appViewModel: appViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings
            ))
            .modifier(ToggleSettingsModifier())
            .background(TrafficLightHider(bgColor: themeColors.bgSubtle))
            .background(WindowCloseGuard(session: session))
            .background(KeyWindowTracker(documentViewModel: documentViewModel))
            .task {
                // ViewModel 间依赖连接已由 WindowSession.init 完成，不在此重复连接。
                applyAppearance(settings.appearanceMode)

                // Task 14：已删除 pendingOpenFilePath/pendingOpenDirectoryPath UserDefaults 后备。
                // 所有打开入口经 WindowCoordinator.enqueue(OpenRequest) 统一路由（Task 8）。
                // restoreLastLocation 由 AppDelegate 经 AppStartupCoordinator 裁决后触发。
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetToWelcome)) { _ in
                resetToWelcome()
            }
            .onReceive(NotificationCenter.default.publisher(for: .restoreLastLocation)) { _ in
                restoreLastLocation()
            }
            .onChange(of: colorScheme) { _, newScheme in
                // 仅在「跟随系统」模式下更新 systemIsDark
                // 避免手动选择浅色/深色时，colorScheme 变化污染 systemIsDark
                if settings.appearanceMode == .system {
                    settings.systemIsDark = (newScheme == .dark)
                }
            }
            .onChange(of: settings.appearanceMode) { _, newMode in
                // 切换到「跟随系统」时，立即刷新 systemIsDark 为当前系统外观
                if newMode == .system {
                    settings.systemIsDark = NSApp.effectiveAppearance
                        .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                }
            }
            // 主题变化时重新计算缓存的主题颜色
            // resolvedTheme 是 Equatable，仅在主题实际变更时触发
            .onChange(of: settings.resolvedTheme) { _, newTheme in
                themeColors = ThemeColors.from(newTheme)
            }
            .onChange(of: documentViewModel.isUntitled) { _, isUntitled in
                if !isUntitled {
                    appViewModel.hasUnsavedUntitled = false
                    appViewModel.untitledFileName = ""
                }
            }
    }

    // MARK: - 布局

    private var mainLayout: some View {
        HStack(spacing: 0) {
            if appViewModel.isShowingSettings {
                // 设置模式：左侧设置菜单
                SettingsSidebarView(appViewModel: appViewModel)
                    .frame(width: appViewModel.sidebarWidth)

                ResizeHandle(appViewModel: appViewModel)
                    .background(themeColors.bgSubtle)

                // 右侧设置内容
                SettingsContentView(appViewModel: appViewModel, settings: settings)
            } else {
                // 正常模式：文件树 + 文档
                // SidebarView 始终保留在视图树中，通过宽度 0 + clipping 隐藏，
                // 避免条件 if 导致 NSView 后端反复销毁/重建，引发 AppKit hit-testing
                // 与 SwiftUI 布局不同步（标题栏拖拽区域吞噬按钮点击）
                SidebarView(
                    fileTreeViewModel: fileTreeViewModel,
                    appViewModel: appViewModel,
                    documentViewModel: documentViewModel,
                    session: session
                )
                .frame(width: appViewModel.isSidebarVisible ? appViewModel.sidebarWidth : 0)
                .clipped()
                .allowsHitTesting(appViewModel.isSidebarVisible)

                if appViewModel.isSidebarVisible {
                    ResizeHandle(appViewModel: appViewModel)
                        .background(themeColors.bgSubtle)
                }

                DetailView(
                    appViewModel: appViewModel,
                    documentViewModel: documentViewModel,
                    fileTreeViewModel: fileTreeViewModel,
                    settings: settings,
                    undoStore: session.undoStore,
                    owningWindow: session.window
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appViewModel.isShowingSettings)
        .overlay {
            if appViewModel.isCommandPaletteVisible {
                ZStack {
                    // 半透明背景（点击关闭）
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            appViewModel.hideCommandPalette()
                        }

                    // 命令面板（标题栏下方居中）
                    VStack(spacing: 0) {
                        Spacer().frame(height: 58)
                        CommandPaletteView(viewModel: commandPaletteViewModel)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: commandPaletteViewModel.isVisible) { _, visible in
            if !visible && appViewModel.isCommandPaletteVisible {
                appViewModel.hideCommandPalette()
            }
        }
        .onChange(of: appViewModel.isCommandPaletteVisible) { _, visible in
            if visible {
                commandPaletteViewModel.configure(
                    appViewModel: appViewModel,
                    fileTreeViewModel: fileTreeViewModel,
                    documentViewModel: documentViewModel,
                    settings: settings
                )
                if !commandPaletteViewModel.isVisible {
                    commandPaletteViewModel.show()
                }
            } else {
                if commandPaletteViewModel.isVisible {
                    commandPaletteViewModel.hide()
                }
            }
        }
    }

    // MARK: - 方法

    private func applyAppearance(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }

    /// 重置所有 ViewModel 状态，显示欢迎页
    /// 用于 Dock 点击重新激活时，避免恢复旧窗口的文档内容
    private func resetToWelcome() {
        commandPaletteViewModel.hide()
        appViewModel.rootDirectory = nil
        appViewModel.isSingleFileMode = false
        appViewModel.singleFileURL = nil
        appViewModel.selectedFile = nil
        appViewModel.hasUnsavedUntitled = false
        appViewModel.untitledFileName = ""
        appViewModel.isShowingSettings = false
        // 欢迎页无目录内容，隐藏 sidebar 避免显示空文件树
        if appViewModel.isSidebarVisible {
            appViewModel.isSidebarVisible = false
        }
        fileTreeViewModel.selectedFileURL = nil
        documentViewModel.clearDocument()
    }

    /// 恢复上次打开的位置（目录或文件）
    /// 用于 Dock 点击重新激活且 reopenLastLocation 开启时
    private func restoreLastLocation() {
        // 如果冷启动已通过 UserDefaults 打开了文件/目录，不覆盖
        // 修复：冷启动双击 md 文件时，applicationDidFinishLaunching 的 0.5s 延迟
        // 可能误发 .restoreLastLocation，覆盖掉 ContentView.task 已打开的文件
        if appViewModel.isSingleFileMode || appViewModel.rootDirectory != nil {
            return
        }
        if let dir = settings.lastOpenedDirectory {
            appViewModel.openDirectory(dir)
            settings.addRecentItem(url: dir, isDirectory: true)
        } else if let file = settings.lastOpenedFile {
            appViewModel.openSingleFile(file)
            fileTreeViewModel.selectedFileURL = file
            settings.addRecentItem(url: file, isDirectory: false)
        } else {
            resetToWelcome()
        }
    }

    // MARK: - 命令面板切换

    /// 切换命令面板（指定模式）
    private func toggleCommandPalette() {
        if appViewModel.isCommandPaletteVisible {
            appViewModel.hideCommandPalette()
            commandPaletteViewModel.hide()
        } else {
            commandPaletteViewModel.configure(
                appViewModel: appViewModel,
                fileTreeViewModel: fileTreeViewModel,
                documentViewModel: documentViewModel,
                settings: settings
            )
            commandPaletteViewModel.show()
            appViewModel.showCommandPalette()
        }
    }
}

// MARK: - 设置侧边栏

/// 设置模式下的左侧菜单视图
struct SettingsSidebarView: View {
    let appViewModel: AppViewModel
    @Environment(\.language) private var language
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部区域：自定义红绿灯（50px）
            HStack(spacing: 0) {
                TrafficLightButtons()
                    .padding(.leading, 12)
                Spacer()
            }
            .frame(height: 50)
            .background(WindowDragArea())

            Rectangle().fill(themeColors.border).frame(height: 1)

            // 返回按钮
            Button {
                appViewModel.hideSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr(.settingsBackToApp, language: language))
                        .font(.system(size: 12))
                }
                .foregroundStyle(themeColors.fgSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // 菜单项
            SettingsMenuItemView(
                title: L10n.tr(.settingsTabGeneral, language: language),
                icon: "gearshape",
                isSelected: appViewModel.settingsTab == .general
            ) {
                appViewModel.settingsTab = .general
            }

            SettingsMenuItemView(
                title: L10n.tr(.settingsTabAppearance, language: language),
                icon: "paintbrush",
                isSelected: appViewModel.settingsTab == .appearance
            ) {
                appViewModel.settingsTab = .appearance
            }

            Spacer()
        }
        .background(themeColors.bgSubtle)
    }
}

private struct SettingsMenuItemView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(isSelected ? themeColors.ink : themeColors.fgSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? themeColors.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - 设置内容视图

/// 设置模式下的右侧内容区域
struct SettingsContentView: View {
    let appViewModel: AppViewModel
    @Bindable var settings: SettingsModel
    @Environment(\.themeColors) private var themeColors

    private var currentLanguage: Language {
        settings.languagePref.resolvedLanguage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch appViewModel.settingsTab {
                case .general:
                    GeneralSettingsView(settings: settings, language: currentLanguage)
                case .appearance:
                    AppearanceSettingsView(settings: settings, language: currentLanguage)
                }
            }
            .frame(minWidth: 480, maxWidth: 896)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
        }
        .scrollIndicators(.automatic)
        .scrollContentBackground(.hidden)
        .background(themeColors.surface, in: .rect(
            topLeadingRadius: 10,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        ))
        .clipShape(.rect(
            topLeadingRadius: 10,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        ))
        .background(themeColors.bgSubtle)
        .overlay(
            LeftEdgeShape(radius: 10)
                .stroke(themeColors.border, lineWidth: 1)
        )
    }
}

// MARK: - 全屏状态监听

private struct FullScreenStateModifier: ViewModifier {
    let appViewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                appViewModel.isFullScreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                appViewModel.isFullScreen = false
            }
    }
}

// MARK: - 快捷键监听
// Task 7：KeyboardShortcutModifier 的窗口级通知监听（toggleSidebar /
// switchToRendered / switchToRaw）已迁移到 FocusedValues 命令路由，
// 该 modifier 不再需要内容，移除以避免冗余广播监听。

// MARK: - 文件打开通知

private struct FileOpenModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel
    /// Task 13：用于判断本窗口是否为最后活动窗口，限制 lastOpened 写入。
    let session: WindowSession

    /// Task 14：ensureWindowVisible 已移除。
    /// 窗口激活由 WindowCoordinator.activate(windowID:) 统一处理，
    /// 不再遍历 NSApp.windows 推断目标窗口。

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openLinkedMarkdownFile)) { notification in
                guard let url = notification.object as? URL else { return }
                handleLinkedMarkdownFileOpen(url.standardizedFileURL)
            }
    }

    /// 打开渲染页内点击的本地 Markdown 链接。
    /// 当前处于目录模式且目标文件仍在根目录内时，只切换文件树选中项，避免退回单文件模式。
    private func handleLinkedMarkdownFileOpen(_ url: URL) {
        if documentViewModel.currentFileURL?.standardizedFileURL == url {
            return
        }

        if documentViewModel.isUntitled && documentViewModel.isDirty {
            handleUnsavedChangesBeforeAction { proceed in
                guard proceed else { return }
                openLinkedMarkdownFile(url)
            }
        } else {
            openLinkedMarkdownFile(url)
        }
    }

    private func openLinkedMarkdownFile(_ url: URL) {
        if let rootDir = appViewModel.rootDirectory,
           isFileURL(url, inside: rootDir) {
            fileTreeViewModel.selectedFileURL = url
            session.recordLastOpened(file: url, directory: nil)
            settings.addRecentItem(url: url, isDirectory: false)
            return
        }

        appViewModel.openSingleFile(url)
        fileTreeViewModel.selectedFileURL = url
        session.recordLastOpened(file: url, directory: nil)
        settings.addRecentItem(url: url, isDirectory: false)
    }

    private func isFileURL(_ fileURL: URL, inside directoryURL: URL) -> Bool {
        let filePath = fileURL.standardizedFileURL.path
        let directoryPath = directoryURL.standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/"
        return filePath.hasPrefix(prefix)
    }

    /// 通用未保存修改弹窗处理
    /// 仅在临时新建文件（isUntitled && isDirty）有未保存更改时调用
    /// 弹窗确认后执行操作，保护临时文件内容不丢失
    /// - Parameter completion: 回调，`proceed` 为 true 表示用户选择保存或放弃，可继续操作；false 表示取消
    private func handleUnsavedChangesBeforeAction(completion: @escaping (_ proceed: Bool) -> Void) {
        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 保存：临时新建文件走另存为流程
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                for: nil,
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    appViewModel.hasUnsavedUntitled = false

                    // 如果保存在当前目录下，刷新文件树
                    if let rootDir = appViewModel.rootDirectory,
                       saveURL.path.hasPrefix(rootDir.path + "/") {
                        await fileTreeViewModel.loadDirectory(rootDir)
                        fileTreeViewModel.selectedFileURL = saveURL
                    }

                    settings.lastOpenedFile = saveURL
                    settings.addRecentItem(url: saveURL, isDirectory: false)
                    completion(true)
                }
            } else {
                // 用户取消了另存为，不继续操作
                completion(false)
            }

        case .alertSecondButtonReturn:
            // 不保存
            documentViewModel.discardUntitledFile()
            appViewModel.hasUnsavedUntitled = false
            completion(true)

        default:
            // 取消
            completion(false)
        }
    }
}

// MARK: - 目录变化

private struct DirectoryChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: appViewModel.rootDirectory) { _, newDirectory in
                if let dir = newDirectory {
                    // 清除选中状态，避免旧选中 URL 与新目录状态不同步
                    // （例如：从单文件模式切到目录模式时，selectedFileURL 仍指向旧文件，
                    // 但 documentViewModel 已被清空，导致点击同一文件不触发 onChange）
                    fileTreeViewModel.selectedFileURL = nil
                    documentViewModel.clearDocument()
                    Task {
                        await fileTreeViewModel.loadDirectory(dir)
                    }
                } else {
                    fileTreeViewModel.clearDirectory(clearSelection: false)
                }
            }
    }
}

// MARK: - 文件选中变化

private struct SelectionChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel

    func body(content: Content) -> some View {
        content
            .onChange(of: fileTreeViewModel.selectedFileURL) { oldURL, newURL in
                if let url = newURL {
                    if documentViewModel.isUntitled && documentViewModel.isDirty {
                        handleFileSwitchWithUnsavedChanges(from: oldURL, to: url)
                    } else {
                        Task {
                            await documentViewModel.loadFile(at: url)
                        }
                        let node = findFileNode(in: fileTreeViewModel.nodes, url: url)
                        appViewModel.selectedFile = node
                    }
                } else {
                    if let deletedURL = oldURL,
                       !FileManager.default.fileExists(atPath: deletedURL.path),
                       documentViewModel.isDirty {
                        handleDeletedFileWithUnsavedChanges(deletedURL)
                    } else if !documentViewModel.isUntitled && !appViewModel.isSingleFileMode {
                        // 单文件模式下不响应 selectedFileURL 变 nil 而取消文档
                        // 单文件模式的文档生命周期应独立于文件树选中状态
                        documentViewModel.deselectCurrentFile()
                    }
                    appViewModel.selectedFile = nil
                }
            }
    }

    /// 文件切换时的未保存修改弹窗（仅临时新建文件触发）
    private func handleFileSwitchWithUnsavedChanges(from oldURL: URL?, to newURL: URL) {
        guard documentViewModel.currentFileURL != newURL else { return }

        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 保存：临时新建文件走另存为流程
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                for: nil,
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    appViewModel.hasUnsavedUntitled = false
                    await documentViewModel.loadFile(at: newURL)
                    let node = findFileNode(in: fileTreeViewModel.nodes, url: newURL)
                    appViewModel.selectedFile = node

                    if let rootDir = appViewModel.rootDirectory,
                       saveURL.path.hasPrefix(rootDir.path + "/") {
                        await fileTreeViewModel.loadDirectory(rootDir)
                        fileTreeViewModel.selectedFileURL = saveURL
                    }
                }
            } else {
                fileTreeViewModel.selectedFileURL = oldURL
            }

        case .alertSecondButtonReturn:
            documentViewModel.discardUntitledFile()
            appViewModel.hasUnsavedUntitled = false
            Task {
                await documentViewModel.loadFile(at: newURL)
            }
            let node = findFileNode(in: fileTreeViewModel.nodes, url: newURL)
            appViewModel.selectedFile = node

        default:
            fileTreeViewModel.selectedFileURL = oldURL
        }
    }

    /// 处理文件被外部删除且有未保存修改的情况
    private func handleDeletedFileWithUnsavedChanges(_ deletedURL: URL) {
        let language = settings.languagePref.resolvedLanguage
        let fileName = deletedURL.lastPathComponent

        let alert = NSAlert()
        alert.messageText = L10n.tr(.fileDeletedTitle, language: language)
        alert.informativeText = L10n.tr(.fileDeletedMessage, language: language, args: ["name": fileName])
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.fileDeletedSaveAs, language: language))
        alert.addButton(withTitle: L10n.tr(.fileDeletedDiscard, language: language))

        // 「另存为」为默认按钮（回车键）
        alert.buttons[0].keyEquivalent = "\r"
        // 「放弃更改」为 Esc 或 Cmd+D
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 另存为
            let defaultDir = settings.lastOpenedDirectory ?? deletedURL.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                for: nil,
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    documentViewModel.deselectCurrentFile()
                    appViewModel.selectedFile = nil

                    // 如果保存在当前目录下，刷新文件树并选中
                    if let rootDir = appViewModel.rootDirectory,
                       saveURL.path.hasPrefix(rootDir.path) {
                        await fileTreeViewModel.refreshDirectory()
                        fileTreeViewModel.selectedFileURL = saveURL
                    }
                }
            } else {
                // 用户取消了另存为，保留当前文档内容让用户继续操作
                // 但文件树中已无此文件，需要重新选中以避免状态不一致
                appViewModel.selectedFile = nil
            }

        default:
            // 放弃更改
            documentViewModel.deselectCurrentFile()
            appViewModel.selectedFile = nil
        }
    }

    private func findFileNode(in nodes: [FileNode], url: URL) -> FileNode? {
        for node in nodes {
            if node.path == url { return node }
            if node.isDirectory, let children = node.children {
                if let found = findFileNode(in: children, url: url) { return found }
            }
        }
        return nil
    }
}

// MARK: - 设置变化

private struct SettingsChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.showHiddenFiles) { _, _ in reloadFileTree() }
            .onChange(of: settings.showNonMarkdownFiles) { _, _ in reloadFileTree() }
            .onChange(of: settings.languagePref.resolvedLanguage) { _, newLanguage in
                fileTreeViewModel.language = newLanguage
            }
    }

    private func reloadFileTree() {
        guard let dir = appViewModel.rootDirectory else { return }
        fileTreeViewModel.selectedFileURL = nil
        Task {
            await fileTreeViewModel.loadDirectory(dir)
        }
    }
}

// MARK: - 切换设置（Cmd+,）
// Task 7：toggleSettings 已迁移到 FocusedValues 命令路由，此 modifier 不再监听通知。
private struct ToggleSettingsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

// MARK: - 隐藏红绿灯

/// 通过 NSViewRepresentable 隐藏窗口红绿灯按钮
/// viewDidMoveToWindow 在视图挂载到窗口时调用，确保能获取到 window 实例
private struct TrafficLightHider: NSViewRepresentable {
    let bgColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = TrafficLightObserverView()
        view.bgColor = NSColor(bgColor)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let observer = nsView as? TrafficLightObserverView {
            observer.bgColor = NSColor(bgColor)
            observer.updateWindowBackground()
        }
    }

    private final class TrafficLightObserverView: NSView {
        var bgColor: NSColor = .windowBackgroundColor

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // 隐藏红绿灯按钮
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            // 确保内容延伸到标题栏区域
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            // 移除标题栏底部分隔线
            window.titlebarSeparatorStyle = .none
            // 设置窗口背景色匹配 bgSubtle
            updateWindowBackground()
            // 初始化 NSWindow.undoManager swizzling
            // 替换窗口的 undoManager getter 返回 per-file UndoManager
            NSWindow.swizzleUndoManager()
        }

        func updateWindowBackground() {
            guard let window else { return }
            window.backgroundColor = bgColor
        }
    }
}

// MARK: - 主窗口 key 状态追踪

/// 追踪当前 ContentView 所在 NSWindow 是否为 key 窗口，并写入 DocumentViewModel.isKeyWindow。
///
/// 修复「无限弹出保存框」根因：macOS 26 WindowGroup 在文件打开事件时可能创建隐藏的第二窗口，
/// 第二个 ContentView 实例会独立监听 .saveFile / .saveAsFile / .newFile 通知并各自弹框。
/// 通过本追踪器，仅 key 窗口的 ContentView 处理这些通知，隐藏 / 非前台窗口被静默跳过。
private struct KeyWindowTracker: NSViewRepresentable {
    let documentViewModel: DocumentViewModel

    func makeNSView(context: Context) -> NSView {
        let view = KeyWindowObserverView()
        view.documentViewModel = documentViewModel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyWindowObserverView)?.documentViewModel = documentViewModel
    }

    private final class KeyWindowObserverView: NSView {
        weak var documentViewModel: DocumentViewModel?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
            guard let window else {
                documentViewModel?.isKeyWindow = false
                return
            }
            documentViewModel?.isKeyWindow = window.isKeyWindow
            let center = NotificationCenter.default
            let became = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let noted = note.object as? NSWindow, noted === self.window else { return }
                Task { @MainActor in self.documentViewModel?.isKeyWindow = true }
            }
            let resigned = center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let noted = note.object as? NSWindow, noted === self.window else { return }
                Task { @MainActor in self.documentViewModel?.isKeyWindow = false }
            }
            observers = [became, resigned]
        }
    }
}

// MARK: - 窗口关闭保护（Task 12：委托 TerminationCoordinator）

/// 通过 NSViewRepresentable 设置窗口代理，关闭前委托 TerminationCoordinator 询问所属 session。
private struct WindowCloseGuard: NSViewRepresentable {
    let session: WindowSession

    func makeNSView(context: Context) -> NSView {
        let view = WindowCloseGuardView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowCloseGuardView)?.session = session
    }

    private final class WindowCloseGuardView: NSView, NSWindowDelegate {
        weak var session: WindowSession?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let session else { return true }
            // Task 12：委托 TerminationCoordinator 的 shouldClose 逻辑
            // TerminationCoordinator 从 AppDelegate 获取，这里通过 session.coordinator 间接访问
            let decision = session.prepareForClose()
            switch decision {
            case .close:
                return true
            case .needsUntitledDecision:
                // 弹窗逻辑在 ApplicationTerminationCoordinator.presentUntitledSaveAlert
                // 但 headless 测试无法弹 alert，这里直接用内联逻辑
                return WindowCloseGuard.presentUntitledSaveAlert(for: session)
            case .cancel:
                return false
            }
        }
    }

    /// 弹出未保存 Untitled 的保存/不保存/取消对话框。
    @MainActor
    private static func presentUntitledSaveAlert(for session: WindowSession) -> Bool {
        let doc = session.documentViewModel
        let settings = SettingsModel.shared
        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = doc.fileName.isEmpty ? "Untitled.md" : doc.fileName
            guard let saveURL = OpenPanelHelper.showSavePanel(
                for: session.window,
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) else {
                return false
            }
            let semaphore = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await doc.saveAs(to: saveURL)
                semaphore.signal()
            }
            semaphore.wait()
            return true
        case .alertSecondButtonReturn:
            doc.discardUntitledFile()
            return true
        default:
            return false
        }
    }
}
