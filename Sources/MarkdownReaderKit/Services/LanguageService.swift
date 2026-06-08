import Foundation

// MARK: - 实际语言

/// 应用支持的语言，参照 buddy-macos 的 Language 类型
public enum Language: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case en = "en"

    public var id: String { rawValue }

    /// 各语言的本地化显示名称（通过 L10n 渲染，避免硬编码中文）
    public func localizedName(_ language: Language) -> String {
        switch self {
        case .zhCN: L10n.tr(.languageZhCN, language: language)
        case .zhTW: L10n.tr(.languageZhTW, language: language)
        case .en: L10n.tr(.languageEn, language: language)
        }
    }
}

// MARK: - 语言偏好（含「自动」选项）

/// 语言偏好设置，参照 buddy-macos 的 LanguagePref 类型
/// auto 表示跟随系统语言，其余为手动指定
public enum LanguagePref: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case en = "en"

    public var id: String { rawValue }

    /// 解析为实际语言
    /// auto 时自动检测系统语言，手动指定时直接返回对应语言
    public var resolvedLanguage: Language {
        switch self {
        case .auto: LanguageService.detectLanguage()
        case .zhCN: .zhCN
        case .zhTW: .zhTW
        case .en: .en
        }
    }

    /// 从 LanguagePref 转换为 Language（非 auto 时）
    public var toLanguage: Language? {
        Language(rawValue: rawValue)
    }
}

// MARK: - 语言检测服务

/// 语言检测服务，参照 buddy-macos 的 detectLanguage()
/// 使用 Locale API 检测系统语言，区分简体中文和繁体中文
public enum LanguageService {

    /// 检测系统当前语言
    /// 优先使用 Locale.current，通过 languageCode + script/region 判断
    /// - 简体中文：zh 且非 Hant 脚本且非 TW/HK/MO 地区
    /// - 繁体中文：zh 且 Hant 脚本或 TW/HK/MO 地区
    /// - 英文：en
    /// - 其他：默认英文
    public static func detectLanguage() -> Language {
        let locale = Locale.current
        let languageCode = locale.language.languageCode?.identifier ?? ""
        let script = locale.language.script?.identifier ?? ""
        let region = locale.region?.identifier ?? ""

        if languageCode == "zh" {
            // 判断繁体：Hant 脚本或 TW/HK/MO 地区
            if script == "Hant" || ["TW", "HK", "MO"].contains(region) {
                return .zhTW
            }
            return .zhCN
        }

        if languageCode == "en" {
            return .en
        }

        // 默认英文
        return .en
    }
}
