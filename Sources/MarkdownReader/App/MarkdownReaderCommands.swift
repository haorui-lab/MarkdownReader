import SwiftUI
import MarkdownReaderKit

/// 窗口级菜单命令（Task 7）。
///
/// 把原本无目标的 `NotificationCenter.default.post` 菜单动作改为读取焦点窗口的
/// `WindowCommandTarget` 并转发命令。命令只作用于当前焦点窗口，不广播给全部窗口。
/// 应用级命令（About / 检查更新 / 清除最近记录 / 帮助）仍走应用服务。
struct MarkdownReaderCommands: Commands {

    /// 当前界面语言（非视图场景）。
    let language: Language

    var body: some Commands {
        // 文件菜单：新建 + 保存 + 导出 PDF（Open / 打开最近由 Task 8 统一路由）
        CommandGroup(replacing: .newItem) {
            Button(L10n.tr(.menuNewFile, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.newFile)
            }
            .keyboardShortcut("n", modifiers: .command)

           Button(L10n.tr(.open, language: language) + "...") {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.openPanel)
           }
           .keyboardShortcut("o", modifiers: .command)

            Button(L10n.tr(.titleBarSave, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.save)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(L10n.tr(.exportPDF, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.exportPDF)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
        }

        // 替换系统默认 Save/Save As：仅保留关闭（Cmd+W），保存面板走自定义路由
        CommandGroup(replacing: .saveItem) {
            Button(L10n.tr(.closeWindow, language: language)) {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // 设置菜单：Cmd+, 切换窗口内设置；检查更新为应用级
        CommandGroup(replacing: .appSettings) {
            Button(L10n.tr(.settingsMenuLabel, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.toggleSettings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(L10n.tr(.checkForUpdates, language: language)) {
                NotificationCenter.default.post(name: .checkForUpdates, object: nil)
            }
        }

        // 关于（应用级）
        CommandGroup(replacing: .appInfo) {
            Button(L10n.tr(.aboutTitle, language: language)) {
                AboutWindowController.show(language: language)
            }
        }

        // 视图菜单
        CommandGroup(after: .toolbar) {
            Button(L10n.tr(.titleBarToggleSidebar, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.toggleSidebar)
            }
            .keyboardShortcut("\\", modifiers: .command)

            Button(L10n.tr(.commandPaletteTitle, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.toggleCommandPalette)
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button(L10n.tr(.displayModeRendered, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.switchDisplayMode(.rendered))
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(L10n.tr(.displayModeRaw, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.switchDisplayMode(.raw))
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(L10n.tr(.viewZoomIn, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.zoomIn)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button(L10n.tr(.viewZoomOut, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button(L10n.tr(.viewZoomReset, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.zoomReset)
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        // 查找菜单
        CommandMenu(L10n.tr(.findBarFind, language: language)) {
            Button(L10n.tr(.findBarFind, language: language) + "\u{2026}") {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.findInDocument)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(L10n.tr(.findBarFindNext, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.findNext)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button(L10n.tr(.findBarFindPrevious, language: language)) {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.findPrevious)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(L10n.tr(.findBarFindAndReplace, language: language) + "\u{2026}") {
                @FocusedValue(\.windowCommandTarget) var target
                target?.perform(.findAndReplace)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        // 帮助菜单（应用级）
        CommandGroup(replacing: .help) {
            Button(L10n.tr(.helpMarkdownReader, language: language)) {
                if let url = URL(string: "https://davidhoo.github.io/MarkdownReader/help.html") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
