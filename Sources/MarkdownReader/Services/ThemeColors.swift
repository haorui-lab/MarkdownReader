import SwiftUI
import Textual

// MARK: - 主题颜色令牌

/// 从 ThemeDefinition 派生的颜色令牌，参照 buddy-macos 的 deriveTokens()
/// 用于通过 SwiftUI Environment 传递到所有视图
struct ThemeColors: Equatable, Sendable {
    // 核心色
    let surface: Color
    let ink: Color
    let accent: Color
    let success: Color
    let danger: Color

    // 派生背景色
    let bgElevated: Color
    let bgSubtle: Color
    let bgMuted: Color

    // 派生文字色
    let fgSecondary: Color
    let fgMuted: Color

    // 派生强调色
    let accentHover: Color
    let accentSoft: Color

    // 派生边框色
    let border: Color
    let borderSubtle: Color

    // MARK: - 代码块语法高亮主题

    /// 从当前主题色派生 Textual 语法高亮主题
    /// 使用单色 DynamicColor（非 light/dark 双色），确保颜色匹配应用主题而非系统外观
    var highlighterTheme: StructuredText.HighlighterTheme {
        let surfaceNS = NSColor(surface).usingColorSpace(.sRGB) ?? NSColor.black
        let inkNS = NSColor(ink).usingColorSpace(.sRGB) ?? NSColor.white
        let accentNS = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor.blue
        let successNS = NSColor(success).usingColorSpace(.sRGB) ?? NSColor.green
        let dangerNS = NSColor(danger).usingColorSpace(.sRGB) ?? NSColor.red

        let isDark = surfaceNS.perceivedBrightness < inkNS.perceivedBrightness

        let codeForeground = DynamicColor(isDark
            ? ink.opacity(0.85)
            : ink.opacity(0.88))

        let codeBackground = DynamicColor(isDark
            ? surface.mixed(with: ink, fraction: 0.06)
            : surface.mixed(with: ink, fraction: 0.04))

        let keywordColor = DynamicColor(accent)
        let builtinColor = DynamicColor(Color(nsColor: accentNS.blended(with: 0.3, of: inkNS) ?? accentNS))
        let stringColor = DynamicColor(isDark
            ? success.lighter(by: 0.15)
            : Color(nsColor: successNS.blended(with: 0.15, of: inkNS) ?? successNS))
        let charColor = DynamicColor(Color(nsColor: accentNS.blended(with: 0.4, of: successNS) ?? accentNS))
        let numberColor = DynamicColor(Color(nsColor: accentNS.blended(with: 0.25, of: dangerNS) ?? accentNS))
        let classColor = DynamicColor(success)
        let functionColor = DynamicColor(Color(nsColor: accentNS.blended(with: 0.4, of: inkNS) ?? accentNS))
        let variableColor = DynamicColor(Color(nsColor: inkNS.blended(with: 0.15, of: successNS) ?? inkNS))
        let commentColor = DynamicColor(fgMuted)
        let preprocessorColor = DynamicColor(Color(nsColor: dangerNS.blended(with: 0.3, of: accentNS) ?? dangerNS))
        let attributeColor = DynamicColor(Color(nsColor: accentNS.blended(with: 0.3, of: dangerNS) ?? accentNS))
        let urlColor = DynamicColor(accent)
        let insertedColor = DynamicColor(success)
        let deletedColor = DynamicColor(danger)
        let markColor = DynamicColor(fgSecondary)

        return StructuredText.HighlighterTheme(
            foregroundColor: codeForeground,
            backgroundColor: codeBackground,
            tokenProperties: [
                .keyword: AnyTextProperty(.foregroundColor(keywordColor), .fontWeight(.semibold)),
                .builtin: AnyTextProperty(.foregroundColor(builtinColor)),
                .literal: AnyTextProperty(.foregroundColor(keywordColor), .fontWeight(.semibold)),
                .string: AnyTextProperty(.foregroundColor(stringColor)),
                .char: AnyTextProperty(.foregroundColor(charColor)),
                .regex: AnyTextProperty(.foregroundColor(stringColor)),
                .url: AnyTextProperty(.foregroundColor(urlColor)),
                .number: AnyTextProperty(.foregroundColor(numberColor)),
                .symbol: AnyTextProperty(.foregroundColor(codeForeground)),
                .boolean: AnyTextProperty(.foregroundColor(keywordColor), .fontWeight(.semibold)),
                .className: AnyTextProperty(.foregroundColor(classColor)),
                .function: AnyTextProperty(.foregroundColor(functionColor)),
                .functionName: AnyTextProperty(.foregroundColor(functionColor)),
                .variable: AnyTextProperty(.foregroundColor(variableColor)),
                .constant: AnyTextProperty(.foregroundColor(variableColor)),
                .property: AnyTextProperty(.foregroundColor(variableColor)),
                .comment: AnyTextProperty(.foregroundColor(commentColor)),
                .blockComment: AnyTextProperty(.foregroundColor(commentColor)),
                .docComment: AnyTextProperty(.foregroundColor(commentColor)),
                .mark: AnyTextProperty(.foregroundColor(markColor), .fontWeight(.bold)),
                .preprocessor: AnyTextProperty(.foregroundColor(preprocessorColor)),
                .directive: AnyTextProperty(.foregroundColor(preprocessorColor)),
                .attribute: AnyTextProperty(.foregroundColor(attributeColor)),
                .tag: AnyTextProperty(.foregroundColor(charColor)),
                .attributeName: AnyTextProperty(.foregroundColor(attributeColor)),
                .inserted: AnyTextProperty(.foregroundColor(insertedColor)),
                .deleted: AnyTextProperty(.foregroundColor(deletedColor)),
            ]
        )
    }

    /// 从 ThemeDefinition 和对比度派生颜色
    static func from(_ theme: ThemeDefinition) -> ThemeColors {
        let c = Double(theme.contrast) / 100.0
        let isDark = theme.type == .dark

        let surface = Color(hex: theme.surface) ?? .black
        let ink = Color(hex: theme.ink) ?? .white
        let accent = Color(hex: theme.accent) ?? .blue
        let success = Color(hex: theme.success) ?? .green
        let danger = Color(hex: theme.danger) ?? .red

        return ThemeColors(
            surface: surface,
            ink: ink,
            accent: accent,
            success: success,
            danger: danger,
            bgElevated: isDark
                ? surface.mixed(with: ink, fraction: 0.08 + c * 0.08)
                : surface.mixed(with: ink, fraction: 0.16 + c * 0.12),
            bgSubtle: isDark
                ? ink.opacity(0.02 + c * 0.02)
                : surface.mixed(with: ink, fraction: 0.08 + c * 0.08),
            bgMuted: isDark
                ? ink.opacity(0.04 + c * 0.03)
                : surface.mixed(with: ink, fraction: 0.12 + c * 0.10),
            fgSecondary: ink.opacity(0.65 + c * 0.10),
            fgMuted: isDark
                ? ink.opacity(0.42 + c * 0.13)
                : ink.opacity(0.45 + c * 0.10),
            accentHover: isDark
                ? accent.lighter(by: 0.12)
                : accent.darker(by: 0.08),
            accentSoft: isDark
                ? Color.black.mixed(with: accent, fraction: 0.20 + c * 0.08)
                : surface.mixed(with: accent, fraction: 0.11 + c * 0.04),
            border: ink.opacity(0.06 + c * 0.04),
            borderSubtle: ink.opacity(0.04 + c * 0.02)
        )
    }
}

// MARK: - SwiftUI Environment 支持

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors.from(
        ThemeDefinition(id: "buddy-dark", name: "Default Dark", type: .dark,
                        surface: "#18181a", ink: "#e8e8e3", accent: "#339cff",
                        success: "#40c977", danger: "#fa423e", contrast: 60)
    )
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

extension View {
    func applyThemeColors(_ colors: ThemeColors) -> some View {
        environment(\.themeColors, colors)
    }
}

// MARK: - Color 混合辅助

extension Color {
    /// 将两个颜色按比例混合
    func mixed(with other: Color, fraction: Double) -> Color {
        let selfNS = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let otherNS = NSColor(other).usingColorSpace(.sRGB) ?? NSColor.white
        let r = selfNS.redComponent * (1 - fraction) + otherNS.redComponent * fraction
        let g = selfNS.greenComponent * (1 - fraction) + otherNS.greenComponent * fraction
        let b = selfNS.blueComponent * (1 - fraction) + otherNS.blueComponent * fraction
        return Color(red: r, green: g, blue: b)
    }

    /// 变亮
    func lighter(by amount: Double) -> Color {
        mixed(with: .white, fraction: amount)
    }

    /// 变暗
    func darker(by amount: Double) -> Color {
        mixed(with: .black, fraction: amount)
    }
}
