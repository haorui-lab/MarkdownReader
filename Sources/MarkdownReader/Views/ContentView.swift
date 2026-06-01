import SwiftUI

/// 主视图，管理自定义 HStack 两列布局
struct ContentView: View {
    @State private var appViewModel = AppViewModel()
    @State private var fileTreeViewModel = FileTreeViewModel()
    @State private var documentViewModel = DocumentViewModel()
    @State private var gitViewModel = GitViewModel()
    @State private var settings = SettingsModel.shared

    var body: some View {
        mainLayout
            .frame(minWidth: 650, minHeight: 450)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(appViewModel.windowTitle)
            .environment(\.language, settings.languagePref.resolvedLanguage)
            .modifier(FullScreenStateModifier(appViewModel: appViewModel))
            .modifier(KeyboardShortcutModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel
            ))
            .modifier(FileOpenModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                settings: settings
            ))
            .modifier(DirectoryChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel
            ))
            .modifier(SelectionChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel
            ))
            .modifier(SettingsChangeModifier(
                appViewModel: appViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings
            ))
            .modifier(GitStatusModifier(
                appViewModel: appViewModel,
                gitViewModel: gitViewModel
            ))
            .task {
                applyAppearance(settings.appearanceMode)
                if settings.reopenLastLocation {
                    restoreLastLocation()
                }
            }
    }

    // MARK: - 布局

    private var mainLayout: some View {
        HStack(spacing: 0) {
            if appViewModel.isSidebarVisible && !appViewModel.isSingleFileMode {
                SidebarView(
                    fileTreeViewModel: fileTreeViewModel,
                    appViewModel: appViewModel
                )
                .frame(width: appViewModel.sidebarWidth)

                ResizeHandle(appViewModel: appViewModel)
            }

            DetailView(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                gitViewModel: gitViewModel,
                settings: settings
            )
        }
    }

    // MARK: - 方法

    private func applyAppearance(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }

    private func restoreLastLocation() {
        if let dir = settings.lastOpenedDirectory {
            appViewModel.openDirectory(dir)
        } else if let file = settings.lastOpenedFile {
            appViewModel.openSingleFile(file)
            Task {
                await documentViewModel.loadFile(at: file)
            }
        }
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

private struct KeyboardShortcutModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                if !appViewModel.isSingleFileMode {
                    appViewModel.toggleSidebar()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToRendered)) { _ in
                documentViewModel.switchDisplayMode(.rendered)
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToSource)) { _ in
                documentViewModel.switchDisplayMode(.source)
            }
    }
}

// MARK: - 文件打开通知

private struct FileOpenModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let settings: SettingsModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openDirectory)) { notification in
                if let url = notification.object as? URL {
                    appViewModel.openDirectory(url)
                    settings.lastOpenedDirectory = url
                    settings.lastOpenedFile = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFile)) { notification in
                if let url = notification.object as? URL {
                    appViewModel.openSingleFile(url)
                    settings.lastOpenedDirectory = nil
                    settings.lastOpenedFile = url
                    Task {
                        await documentViewModel.loadFile(at: url)
                    }
                }
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
                    documentViewModel.clearDocument()
                    Task {
                        await fileTreeViewModel.loadDirectory(dir)
                    }
                }
            }
    }
}

// MARK: - 文件选中变化

private struct SelectionChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: fileTreeViewModel.selectedFileURL) { _, newURL in
                if let url = newURL {
                    Task {
                        await documentViewModel.loadFile(at: url)
                    }
                    let node = findFileNode(in: fileTreeViewModel.nodes, url: url)
                    appViewModel.selectedFile = node
                }
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
    }

    private func reloadFileTree() {
        guard let dir = appViewModel.rootDirectory else { return }
        fileTreeViewModel.selectedFileURL = nil
        Task {
            await fileTreeViewModel.loadDirectory(dir)
        }
    }
}

// MARK: - Git 状态刷新

private struct GitStatusModifier: ViewModifier {
    let appViewModel: AppViewModel
    let gitViewModel: GitViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: appViewModel.rootDirectory) { _, _ in
                gitViewModel.refreshStatus(directory: appViewModel.rootDirectory)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDirectory)) { _ in
                gitViewModel.refreshStatus(directory: appViewModel.rootDirectory)
            }
    }
}
