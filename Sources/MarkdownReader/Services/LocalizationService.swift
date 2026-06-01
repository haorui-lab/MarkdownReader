import SwiftUI

// MARK: - 本地化服务

/// 简易本地化服务，参照 buddy-macos 的 i18n 字典方案
/// 使用扁平 key-value 结构，支持插值 {n}
enum L10n {

    // MARK: - Key 定义

    /// 所有本地化键，与 buddy-macos 的 settings key 结构对齐
    enum Key: String, CaseIterable, Sendable {
        // 应用名称
        case appName

        // 设置 - 标签页
        case settingsTabGeneral
        case settingsTabAppearance

        // 设置 - 通用
        case settingsGeneralLanguageTitle
        case settingsGeneralLanguageDesc
        case settingsGeneralDisplayTitle
        case settingsGeneralDisplayMode

        // 设置 - 启动
        case settingsGeneralStartupTitle
        case settingsGeneralReopenLastLocation

        // 设置 - 文件树
        case settingsGeneralFileTreeTitle
        case settingsGeneralShowHiddenFiles
        case settingsGeneralShowNonMarkdownFiles

        // 设置 - 外观
        case settingsAppearanceThemeTitle
        case settingsAppearanceMode
        case settingsAppearanceModeLight
        case settingsAppearanceModeDark
        case settingsAppearanceModeSystem
        case settingsAppearanceTypographyTitle
        case settingsAppearanceSourceFontSize
        case settingsAppearanceContentPadding

        // 语言选项
        case languageAuto
        case languageZhCN
        case languageZhTW
        case languageEn

        // 显示模式
        case displayModeRendered
        case displayModeSource

        // 通用操作
        case open

        // 标题栏
        case titleBarToggleSidebar
        case titleBarDisplayMode
        case titleBarOpen

        // 侧边栏
        case loading
        case emptyDirectoryMessage
        case sidebarSettings

        // 欢迎页
        case welcomeOpenFolder
        case welcomePressCmdO

        // Git 状态
        case gitChangesCount
        case gitNoChanges
        case gitCommitMessage
        case gitPushing
        case gitCommitAndPush
        case gitStaged
        case gitModified
        case gitUntracked
    }

    // MARK: - 翻译字典

    private static let en: [Key: String] = [
        .appName: "Markdown Reader",
        .settingsTabGeneral: "General",
        .settingsTabAppearance: "Appearance",
        .settingsGeneralLanguageTitle: "Language",
        .settingsGeneralLanguageDesc: "Choose the interface language. \"Auto\" follows your system.",
        .settingsGeneralDisplayTitle: "Display",
        .settingsGeneralDisplayMode: "Default display mode",
        .settingsGeneralStartupTitle: "Startup",
        .settingsGeneralReopenLastLocation: "Reopen last location on launch",
        .settingsGeneralFileTreeTitle: "File Tree",
        .settingsGeneralShowHiddenFiles: "Show hidden files",
        .settingsGeneralShowNonMarkdownFiles: "Show non-Markdown files",
        .settingsAppearanceThemeTitle: "Theme",
        .settingsAppearanceMode: "Appearance mode",
        .settingsAppearanceModeLight: "Light",
        .settingsAppearanceModeDark: "Dark",
        .settingsAppearanceModeSystem: "Follow System",
        .settingsAppearanceTypographyTitle: "Typography",
        .settingsAppearanceSourceFontSize: "Source font size",
        .settingsAppearanceContentPadding: "Content padding",
        .languageAuto: "Auto / Auto Detect",
        .languageZhCN: "Simplified Chinese",
        .languageZhTW: "Traditional Chinese",
        .languageEn: "English",
        .displayModeRendered: "Rendered",
        .displayModeSource: "Source",
        .open: "Open",
        .titleBarToggleSidebar: "Toggle Sidebar (⌘\\)",
        .titleBarDisplayMode: "Display Mode",
        .titleBarOpen: "Open (⌘O)",
        .loading: "Loading...",
        .emptyDirectoryMessage: "No Markdown files in this directory",
        .sidebarSettings: "Settings (⌘,)",
        .welcomeOpenFolder: "Open a folder to get started",
        .welcomePressCmdO: "Press Cmd+O or click Open in toolbar",
        .gitChangesCount: "{n} changes",
        .gitNoChanges: "No changes",
        .gitCommitMessage: "Commit message",
        .gitPushing: "Pushing...",
        .gitCommitAndPush: "Commit & Push",
        .gitStaged: "Staged",
        .gitModified: "Modified",
        .gitUntracked: "Untracked",
    ]

    private static let zhCN: [Key: String] = [
        .appName: "Markdown Reader",
        .settingsTabGeneral: "通用",
        .settingsTabAppearance: "外观",
        .settingsGeneralLanguageTitle: "界面语言",
        .settingsGeneralLanguageDesc: "选择应用界面的语言。「自动检测」会跟随系统。",
        .settingsGeneralDisplayTitle: "显示",
        .settingsGeneralDisplayMode: "默认显示模式",
        .settingsGeneralStartupTitle: "启动",
        .settingsGeneralReopenLastLocation: "启动时重新打开上次位置",
        .settingsGeneralFileTreeTitle: "文件树",
        .settingsGeneralShowHiddenFiles: "显示隐藏文件",
        .settingsGeneralShowNonMarkdownFiles: "显示非 Markdown 文件",
        .settingsAppearanceThemeTitle: "主题",
        .settingsAppearanceMode: "外观模式",
        .settingsAppearanceModeLight: "浅色",
        .settingsAppearanceModeDark: "深色",
        .settingsAppearanceModeSystem: "跟随系统",
        .settingsAppearanceTypographyTitle: "字体与排版",
        .settingsAppearanceSourceFontSize: "源码字号",
        .settingsAppearanceContentPadding: "内容边距",
        .languageAuto: "自动检测",
        .languageZhCN: "简体中文",
        .languageZhTW: "繁體中文",
        .languageEn: "English",
        .displayModeRendered: "渲染",
        .displayModeSource: "源码",
        .open: "打开",
        .titleBarToggleSidebar: "切换侧边栏 (⌘\\)",
        .titleBarDisplayMode: "显示模式",
        .titleBarOpen: "打开 (⌘O)",
        .loading: "加载中...",
        .emptyDirectoryMessage: "该目录下无 Markdown 文件",
        .sidebarSettings: "设置 (⌘,)",
        .welcomeOpenFolder: "打开文件夹开始阅读",
        .welcomePressCmdO: "按 Cmd+O 或点击工具栏中的打开按钮",
        .gitChangesCount: "{n} 个变更",
        .gitNoChanges: "无变更",
        .gitCommitMessage: "提交消息",
        .gitPushing: "推送中",
        .gitCommitAndPush: "提交并推送",
        .gitStaged: "已暂存",
        .gitModified: "已修改",
        .gitUntracked: "未跟踪",
    ]

    private static let zhTW: [Key: String] = [
        .appName: "Markdown Reader",
        .settingsTabGeneral: "一般",
        .settingsTabAppearance: "外觀",
        .settingsGeneralLanguageTitle: "介面語言",
        .settingsGeneralLanguageDesc: "選擇應用介面的語言。「自動偵測」會跟隨系統。",
        .settingsGeneralDisplayTitle: "顯示",
        .settingsGeneralDisplayMode: "預設顯示模式",
        .settingsGeneralStartupTitle: "啟動",
        .settingsGeneralReopenLastLocation: "啟動時重新開啟上次位置",
        .settingsGeneralFileTreeTitle: "檔案樹",
        .settingsGeneralShowHiddenFiles: "顯示隱藏檔案",
        .settingsGeneralShowNonMarkdownFiles: "顯示非 Markdown 檔案",
        .settingsAppearanceThemeTitle: "主題",
        .settingsAppearanceMode: "外觀模式",
        .settingsAppearanceModeLight: "淺色",
        .settingsAppearanceModeDark: "深色",
        .settingsAppearanceModeSystem: "跟隨系統",
        .settingsAppearanceTypographyTitle: "字體與排版",
        .settingsAppearanceSourceFontSize: "原始碼字號",
        .settingsAppearanceContentPadding: "內容邊距",
        .languageAuto: "自動偵測",
        .languageZhCN: "简体中文",
        .languageZhTW: "繁體中文",
        .languageEn: "English",
        .displayModeRendered: "渲染",
        .displayModeSource: "原始碼",
        .open: "開啟",
        .titleBarToggleSidebar: "切換側邊欄 (⌘\\)",
        .titleBarDisplayMode: "顯示模式",
        .titleBarOpen: "開啟 (⌘O)",
        .loading: "載入中...",
        .emptyDirectoryMessage: "此目錄下無 Markdown 檔案",
        .sidebarSettings: "設定 (⌘,)",
        .welcomeOpenFolder: "開啟資料夾開始閱讀",
        .welcomePressCmdO: "按 Cmd+O 或點擊工具列中的開啟按鈕",
        .gitChangesCount: "{n} 個變更",
        .gitNoChanges: "無變更",
        .gitCommitMessage: "提交訊息",
        .gitPushing: "推送中",
        .gitCommitAndPush: "提交並推送",
        .gitStaged: "已暫存",
        .gitModified: "已修改",
        .gitUntracked: "未追蹤",
    ]

    // MARK: - 查找

    /// 根据语言获取翻译字典
    private static func dictionary(for language: Language) -> [Key: String] {
        switch language {
        case .zhCN: zhCN
        case .zhTW: zhTW
        case .en: en
        }
    }

    /// 翻译指定键
    /// - Parameters:
    ///   - key: 本地化键
    ///   - language: 目标语言
    /// - Returns: 翻译后的字符串，找不到则返回 key 的 rawValue
    static func tr(_ key: Key, language: Language) -> String {
        dictionary(for: language)[key] ?? key.rawValue
    }

    /// 翻译指定键，支持插值 {n}
    /// - Parameters:
    ///   - key: 本地化键
    ///   - language: 目标语言
    ///   - args: 插值参数，如 ["n": "5"]
    /// - Returns: 翻译后的字符串
    static func tr(_ key: Key, language: Language, args: [String: String]) -> String {
        var result = tr(key, language: language)
        for (k, v) in args {
            result = result.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return result
    }
}

// MARK: - SwiftUI Environment 支持

/// 语言环境键，用于在视图层次中传递当前语言
private struct LanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: Language = .en
}

extension EnvironmentValues {
    /// 当前界面语言，从 SettingsModel.languagePref.resolvedLanguage 注入
    var language: Language {
        get { self[LanguageEnvironmentKey.self] }
        set { self[LanguageEnvironmentKey.self] = newValue }
    }
}

// MARK: - View 扩展：便捷本地化

extension View {
    /// 注入当前语言到视图环境
    func withLanguage(_ language: Language) -> some View {
        environment(\.language, language)
    }
}
