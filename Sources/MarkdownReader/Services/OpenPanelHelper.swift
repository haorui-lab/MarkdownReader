import SwiftUI
import UniformTypeIdentifiers

/// 打开面板工具，提供统一的 NSOpenPanel / NSSavePanel 调用逻辑
/// MarkdownReaderApp（菜单 Cmd+O）和 ContentView（Sidebar 按钮）共用
enum OpenPanelHelper {

    /// 显示打开面板，用户选择后发送对应通知
    /// - Parameter language: 当前界面语言，用于面板提示文本
    @MainActor
    static func show(language: Language) {
        // 确保应用在前台，避免 NSOpenPanel 被遮挡
        NSApp.activate(ignoringOtherApps: true)

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
                NotificationCenter.default.post(name: .openDirectory, object: url)
            } else {
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }

    /// 显示另存为面板，让用户选择保存位置
    /// - Parameters:
    ///   - language: 当前界面语言
    ///   - defaultDirectory: 默认定位的目录（上次打开文件的位置）
    ///   - suggestedName: 建议的文件名（如 "Untitled.md"）
    /// - Returns: 用户选择的保存 URL，取消返回 nil
    @MainActor
    static func showSavePanel(
        language: Language,
        defaultDirectory: URL? = nil,
        suggestedName: String = "Untitled.md"
    ) -> URL? {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.prompt = L10n.tr(.save, language: language)
        panel.allowedContentTypes = [UTType(filenameExtension: "md")].compactMap { $0 }
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        // 默认定位到上次打开文件的位置
        if let dir = defaultDirectory {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                panel.directoryURL = dir
            } else if dir.pathExtension.isEmpty == false {
                // 如果是文件 URL，定位到其父目录
                panel.directoryURL = dir.deletingLastPathComponent()
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        return nil
    }
}
