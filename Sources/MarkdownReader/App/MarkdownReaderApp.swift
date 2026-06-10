import SwiftUI
import MarkdownReaderKit
import WebKit

@main
struct MarkdownReaderApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 自动更新 ViewModel
    @State private var updateViewModel = UpdateViewModel()

    /// WebView 预热：App 启动时创建隐藏 WebPage，预加载 HTML 模板 + JS 库
    /// 首次打开文件时复用此 page，跳过 WKWebView 冷启动（~120ms → ~15-20ms）
    @State private var warmupPage: WebPage?

    init() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 当前界面语言（从共享 SettingsModel 读取，用于菜单等非视图场景）
    private var language: Language {
        SettingsModel.shared.languagePref.resolvedLanguage
    }

    /// 最近打开记录（从 SettingsModel 读取，用于菜单动态生成）
    private var recentItems: [RecentItem] {
        SettingsModel.shared.recentItems
    }

    /// 预热 WebView：创建隐藏 WebPage 并加载空白 HTML 模板
    /// 让 WKWebView 进程和 JS 引擎提前初始化，首次打开文件时跳过冷启动
    private func warmupWebView() {
        let scheme = URLScheme("mr")!
        let handler = MarkdownURLSchemeHandler(baseURL: nil)
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[scheme] = handler
        let page = WebPage(configuration: configuration)
        let html = """
        <!DOCTYPE html><html><head>
        <link rel="stylesheet" href="mr:///css/markdown.css">
        <link rel="stylesheet" href="mr:///css/katex.min.css">
        <script src="mr:///js/mermaid.min.js"></script>
        <script src="mr:///js/katex.min.js"></script>
        <script src="mr:///js/prism-core.min.js"></script>
        <script src="mr:///js/prism-autoloader.min.js"></script>
        <script>Prism.plugins.autoloader.languages_path = 'mr:///js/';</script>
        <script src="mr:///js/markdown-reader.js"></script>
        </head><body><div class="markdown-preview"><div id="mr-content"></div></div></body></html>
        """
        _ = page.load(html: html, baseURL: URL(string: "about:blank")!)
        warmupPage = page
    }

    /// 打开最近的子菜单（文件在上、目录在下，不显示分区标题）
    @ViewBuilder
    private var openRecentMenu: some View {
        if recentItems.isEmpty {
            Text(L10n.tr(.openRecentEmpty, language: language))
                .disabled(true)
        } else {
            Menu(L10n.tr(.openRecent, language: language)) {
                let files = recentItems.filter { !$0.isDirectory }
                let folders = recentItems.filter { $0.isDirectory }

                // 文件列表
                ForEach(files) { item in
                    Button {
                        NotificationCenter.default.post(name: .openFile, object: item.url)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(item.displayName)
                        }
                    }
                }

                // 分隔线（文件和目录都有时显示）
                if !files.isEmpty && !folders.isEmpty {
                    Divider()
                }

                // 目录列表
                ForEach(folders) { item in
                    Button {
                        NotificationCenter.default.post(name: .openDirectory, object: item.url)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(item.displayName)
                        }
                    }
                }

                Divider()

                Button(L10n.tr(.clearRecentItems, language: language)) {
                    SettingsModel.shared.clearRecentItems()
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // .onOpenURL 在 macOS 15+ 不触发 file-open 事件
                // 保留作为安全网，以防未来 macOS 版本行为变化
                .onOpenURL { url in
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    let name: Notification.Name = isDir.boolValue ? .openDirectory : .openFile
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: name, object: url)
                    }
                }
                // 热启动时路由到现有窗口，而非创建新窗口
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                // 自动更新弹窗
                .sheet(isPresented: $updateViewModel.isShowingUpdateSheet) {
                    UpdateView(viewModel: updateViewModel)
                }
                // 启动时自动检查更新（延迟 2 秒，避免影响启动速度）
                .task {
                    warmupWebView()
                    try? await Task.sleep(for: .seconds(2))
                    updateViewModel.checkForUpdatesAutomatically()
                }
                // 监听手动检查更新通知
                .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
                    updateViewModel.checkForUpdatesManually()
                }
        }
        // .handlesExternalEvents(matching:) scene modifier 已移除
        // 冷启动时 ContentView.task 通过 UserDefaults 读取 AppDelegate 写入的文件路径，
        // 无需 SwiftUI 为外部事件创建额外窗口，避免出现双窗口问题
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.automatic)
        .commands {
            // 设置菜单：Cmd+, → 切换窗口内设置状态
            CommandGroup(replacing: .appInfo) {
                Button(L10n.tr(.aboutTitle, language: language)) {
                    AboutWindowController.show(language: language)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr(.settingsMenuLabel, language: language)) {
                    NotificationCenter.default.post(name: .toggleSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                // 检查更新
                Button(L10n.tr(.checkForUpdates, language: language)) {
                    NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                }
            }

            // 文件菜单：新建 + 打开 + 保存 + 打开最近
            CommandGroup(replacing: .newItem) {
                Button(L10n.tr(.menuNewFile, language: language)) {
                    NotificationCenter.default.post(name: .newFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(L10n.tr(.open, language: language) + "...") {
                    OpenPanelHelper.show(language: language)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(L10n.tr(.titleBarSave, language: language)) {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(L10n.tr(.exportPDF, language: language)) {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                // 打开最近子菜单
                openRecentMenu
            }

            // 视图菜单：Sidebar 切换
            CommandGroup(after: .toolbar) {
                Button(L10n.tr(.titleBarToggleSidebar, language: language)) {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button(L10n.tr(.displayModeRendered, language: language)) {
                    NotificationCenter.default.post(name: .switchToRendered, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(L10n.tr(.displayModeRaw, language: language)) {
                    NotificationCenter.default.post(name: .switchToRaw, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button(L10n.tr(.viewZoomIn, language: language)) {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button(L10n.tr(.viewZoomOut, language: language)) {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button(L10n.tr(.viewZoomReset, language: language)) {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // 查找菜单
            CommandMenu(L10n.tr(.findBarFind, language: language)) {
                Button(L10n.tr(.findBarFind, language: language) + "\u{2026}") {
                    NotificationCenter.default.post(name: .findInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(L10n.tr(.findBarFindNext, language: language)) {
                    NotificationCenter.default.post(name: .findNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button(L10n.tr(.findBarFindPrevious, language: language)) {
                    NotificationCenter.default.post(name: .findPrevious, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button(L10n.tr(.findBarFindAndReplace, language: language) + "\u{2026}") {
                    NotificationCenter.default.post(name: .findAndReplace, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.markdownreader.toggleSidebar")
    static let switchToRendered = Notification.Name("com.markdownreader.switchToRendered")
    static let switchToRaw = Notification.Name("com.markdownreader.switchToRaw")
    static let openDirectory = Notification.Name("com.markdownreader.openDirectory")
    static let openFile = Notification.Name("com.markdownreader.openFile")
    static let toggleSettings = Notification.Name("com.markdownreader.toggleSettings")
    static let newFile = Notification.Name("com.markdownreader.newFile")
    static let saveFile = Notification.Name("com.markdownreader.saveFile")
    static let saveAsFile = Notification.Name("com.markdownreader.saveAsFile")
    static let reloadFile = Notification.Name("com.markdownreader.reloadFile")
    static let clearRecentItems = Notification.Name("com.markdownreader.clearRecentItems")
    static let restoreLastLocation = Notification.Name("com.markdownreader.restoreLastLocation")
    static let resetToWelcome = Notification.Name("com.markdownreader.resetToWelcome")
    static let checkForUpdates = Notification.Name("com.markdownreader.checkForUpdates")
    static let findInDocument = Notification.Name("com.markdownreader.findInDocument")
    static let findNext = Notification.Name("com.markdownreader.findNext")
    static let findPrevious = Notification.Name("com.markdownreader.findPrevious")
    static let findAndReplace = Notification.Name("com.markdownreader.findAndReplace")
    static let exportPDF = Notification.Name("com.markdownreader.exportPDF")
    static let dragHoverChanged = Notification.Name("com.markdownreader.dragHoverChanged")
    static let unsupportedFileTypeDropped = Notification.Name("com.markdownreader.unsupportedFileTypeDropped")
    static let zoomIn = Notification.Name("com.markdownreader.zoomIn")
    static let zoomOut = Notification.Name("com.markdownreader.zoomOut")
    static let zoomReset = Notification.Name("com.markdownreader.zoomReset")
}
