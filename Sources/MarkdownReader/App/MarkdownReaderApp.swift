import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownReaderApp: App {

    init() {
        // 通过 swift run 运行时，macOS 不会自动将应用设为常规前台应用
        // 需要手动设置激活策略并激活，否则：
        // 1. 应用不会出现在 Dock 中
        // 2. 窗口不会成为 key window，影响光标追踪等功能
        // 3. 点击窗口很难将应用带到前台
        //
        // 注意：必须使用 DispatchQueue.main.async 延迟执行，
        // 因为 App.init() 时 NSApp（NSApplication 共享实例）尚未创建，
        // 直接访问 NSApp 会导致 nil 解包崩溃
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 当前界面语言（从共享 SettingsModel 读取，用于菜单等非视图场景）
    private var language: Language {
        SettingsModel.shared.languagePref.resolvedLanguage
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.automatic)
        .commands {
            // 设置菜单：Cmd+,
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr(.settingsTabGeneral, language: language) + "...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 文件菜单：打开
            CommandGroup(replacing: .newItem) {
                Button(L10n.tr(.open, language: language) + "...") {
                    openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
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

                Button(L10n.tr(.displayModeSource, language: language)) {
                    NotificationCenter.default.post(name: .switchToSource, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        // 设置窗口
        Settings {
            SettingsView()
        }
    }

    /// 统一的打开面板，支持选择目录和 .md 文件
    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr(.open, language: language)
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "md")].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                // 目录模式
                NotificationCenter.default.post(name: .openDirectory, object: url)
            } else {
                // 单文件模式
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.markdownreader.toggleSidebar")
    static let switchToRendered = Notification.Name("com.markdownreader.switchToRendered")
    static let switchToSource = Notification.Name("com.markdownreader.switchToSource")
    static let openDirectory = Notification.Name("com.markdownreader.openDirectory")
    static let openFile = Notification.Name("com.markdownreader.openFile")
}
